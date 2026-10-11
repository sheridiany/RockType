import Foundation
import Testing
@testable import RoarkTCore
@testable import RoarkTApp

@Test func longTextSplitPreservesBytesParagraphsAndCode() throws {
    let code = "```swift\r\nlet value = 42\r\n```\r\n"
    let source = String(repeating: "中文🙂 paragraph\r\n\r\n", count: 20) + code + String(repeating: "z", count: 150)
    let parts = try LongTextPlan.split(source, budget: 100)
    #expect(parts.joined() == source)
    #expect(parts.allSatisfy { $0.utf8.count <= 100 })
    #expect(parts.filter { $0.contains(code) }.count == 1)
    #expect(throws: OperationFailure.codeBlockTooLong(limit: 20)) { try LongTextPlan.split(code, budget: 20) }
    #expect(throws: OperationFailure.inputTooLong(limit: LongTextPlan.maximumBytes)) {
        try LongTextPlan.split(String(repeating: "x", count: LongTextPlan.maximumBytes + 1), budget: 8192)
    }
    #expect(throws: OperationFailure.tooManySegments(limit: 64)) { try LongTextPlan.split(String(repeating: "x", count: 65), budget: 1) }
}

private func longRequest(_ id: String = "translate") -> OperationRequest {
    var settings = AppSettings.defaults
    settings.ai.defaultModel = "synthetic"; settings.translation.engine = .ai
    let text = (0..<4).map { "PART\($0)\n" + String(repeating: "x", count: 4900) + "\n\n" }.joined()
    return .init(session: .init(snapshot: .init(text: text, source: .init(pid: 0, applicationName: "Synthetic"), method: .paste)),
        template: OperationTemplate.defaults.first { $0.id == id }!, settings: settings)
}

private actor SegmentProbe {
    var running = 0, peak = 0, calls = 0
    func enter() { running += 1; peak = max(peak, running); calls += 1 }
    func leave() { running -= 1 }
}

@MainActor @Test func longTranslationBoundsConcurrencyOrdersOutputAndSavesOnlyWholeDocument() async throws {
    let probe = SegmentProbe(), recent = InMemoryRecentResults()
    let runner = DefaultOperationRunner(recent: recent, apiKey: { "synthetic" }, isAllowed: { true },
        streamAI: { _, prompt, _, _, delta in
            await probe.enter()
            let number = (0..<4).first { prompt.contains("PART\($0)") }!
            try await Task.sleep(for: .milliseconds(number == 0 ? 80 : 10))
            await delta("chunk\(number)")
            await probe.leave()
            return "chunk\(number)"
        })
    var output = "", result: OperationResult?
    let request = longRequest()
    for await event in runner.run(request) {
        if case .delta(let text) = event { output += text }
        if case .completed(let value) = event { result = value }
        if case .failed(let error) = event { throw error }
    }
    #expect(await probe.peak == 2)
    #expect(output == "chunk0\n\nchunk1\n\nchunk2\n\nchunk3")
    #expect(result?.text == output && result?.session.snapshot == request.session.snapshot)
    #expect(recent.results.count == 1 && recent.results.first?.text == output)
    #expect(result?.session.turns.count == 1)
}

@MainActor @Test func longSummaryReducesOrderedSectionsInsteadOfConcatenatingDuplicates() async throws {
    let probe = SegmentProbe()
    let runner = DefaultOperationRunner(apiKey: { "synthetic" }, isAllowed: { true },
        streamAI: { _, prompt, _, _, _ in
            await probe.enter(); await probe.leave()
            if prompt.contains("以下为按原文顺序排列的分段摘要") {
                #expect(prompt.contains("summary0\n\nsummary1\n\nsummary2\n\nsummary3"))
                return "merged summary"
            }
            return "summary\((0..<4).first { prompt.contains("PART\($0)") }!)"
        })
    var output = ""
    for await event in runner.run(longRequest("summarize")) {
        if case .delta(let value) = event { output += value }
        if case .failed(let error) = event { throw error }
    }
    #expect(output == "merged summary")
    #expect(await probe.calls == 5)
}

@MainActor @Test func longOperationCancellationAndProtectionStopQueuedSegments() async throws {
    for protection in [false, true] {
        let probe = SegmentProbe()
        var allowed = true
        let runner = DefaultOperationRunner(apiKey: { "synthetic" }, isAllowed: { allowed }, streamAI: { _, _, _, _, _ in
            await probe.enter()
            do { try await Task.sleep(for: .seconds(30)); await probe.leave(); return "unexpected" }
            catch { await probe.leave(); throw error }
        })
        let task = Task { var events: [OperationEvent] = []; for await event in runner.run(longRequest()) { events.append(event) }; return events }
        for _ in 0..<200 where await probe.calls < 2 { try await Task.sleep(for: .milliseconds(5)) }
        if protection { allowed = false } else { runner.cancel() }
        let events = await task.value
        #expect(events.contains(protection ? .failed(.protectedInput) : .cancelled))
        for _ in 0..<200 where await probe.running > 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await probe.calls == 2)
        #expect(await probe.running == 0)
        #expect(!events.contains { if case .completed = $0 { return true }; return false })
    }
}

@MainActor @Test func longInputAndAtomicCodeLimitsFailBeforeCredentialsOrNetwork() async throws {
    var keys = 0
    let runner = DefaultOperationRunner(apiKey: { keys += 1; return "synthetic" }, isAllowed: { true }, streamAI: { _, _, _, _, _ in
        Issue.record("Rejected input reached network"); return "unexpected"
    })
    for (text, failure) in [(String(repeating: "x", count: 262_145), OperationFailure.inputTooLong(limit: 262_144)),
                            ("```swift\n" + String(repeating: "x", count: 8192) + "\n```", .codeBlockTooLong(limit: 8192))] {
        let base = longRequest()
        let request = OperationRequest(session: .init(snapshot: .init(text: text, source: base.session.snapshot.source, method: .paste)),
            template: base.template, settings: base.settings)
        var failures: [OperationFailure] = []
        for await event in runner.run(request) { if case .failed(let value) = event { failures.append(value) } }
        #expect(failures == [failure] && keys == 0)
    }
}

@MainActor @Test func longChildFailureCancelsOtherRequestsAndDoesNotCachePartialWork() async throws {
    let probe = SegmentProbe(), recent = InMemoryRecentResults()
    let runner = DefaultOperationRunner(recent: recent, apiKey: { "synthetic" }, isAllowed: { true }, streamAI: { _, prompt, _, _, _ in
        await probe.enter()
        do {
            try await Task.sleep(for: .milliseconds(prompt.contains("PART1") ? 10 : 30_000))
            await probe.leave()
            throw AIClientError.unauthorized
        } catch { if error is CancellationError { await probe.leave() }; throw error }
    })
    var terminal: OperationFailure?
    for await event in runner.run(longRequest()) { if case .failed(let failure) = event { terminal = failure } }
    for _ in 0..<200 where await probe.running > 0 { try await Task.sleep(for: .milliseconds(5)) }
    #expect(terminal == .ai(.unauthorized) && recent.results.isEmpty)
    #expect(await probe.calls == 2)
    #expect(await probe.running == 0)
}

@MainActor @Test func longMixedLanguageUsesDocumentDirectionAndBlankSegmentsStayLocal() async throws {
    let probe = SegmentProbe()
    let runner = DefaultOperationRunner(apiKey: { "synthetic" }, isAllowed: { true }, streamAI: { _, prompt, _, _, _ in
        await probe.enter(); await probe.leave()
        #expect(prompt.hasPrefix("target=en"))
        return "translated"
    })
    var template = OperationTemplate.defaults[0]; template.prompt = "target={{target}}"
    let base = longRequest()
    let text = String(repeating: "\n", count: 8192) + String(repeating: "English ", count: 650)
        + "\n\n" + String(repeating: "中文", count: 900)
    var result: OperationResult?
    for await event in runner.run(.init(session: .init(snapshot: .init(text: text, source: base.session.snapshot.source, method: .paste)),
        template: template, settings: base.settings)) {
        if case .completed(let value) = event { result = value }
        if case .failed(let error) = event { throw error }
    }
    #expect(result != nil)
    #expect(await probe.calls == 2)
}

@Test func oversizedProsePrefersWordBoundariesAndKeepsEmojiClusters() throws {
    let source = String(repeating: "alpha beta 👩🏽‍💻 gamma delta ", count: 100)
    let parts = try LongTextPlan.split(source, budget: 100)
    #expect(parts.joined() == source)
    #expect(parts.allSatisfy { $0.utf8.count <= 100 })
    #expect(parts.dropLast().allSatisfy { $0.last?.isWhitespace == true })
    #expect(parts.filter { $0.contains("👩🏽‍💻") }.count > 1)
}

@MainActor @Test func longSummaryNonCompressingProviderHasFiniteWorkAndNoPartialCache() async throws {
    let probe = SegmentProbe(), recent = InMemoryRecentResults()
    let runner = DefaultOperationRunner(recent: recent, apiKey: { "synthetic" }, isAllowed: { true }, streamAI: { _, _, _, _, _ in
        await probe.enter(); await probe.leave()
        return String(repeating: "synthetic paragraph\n\n", count: 600)
    })
    var failed = false
    for await event in runner.run(longRequest("summarize")) {
        if case .failed(let error) = event {
            failed = error == .ai(.outputLimit) || error == .ai(.responseTooLarge)
        }
        if case .completed = event { Issue.record("Unbounded summaries must not be marked complete") }
    }
    #expect(failed && recent.results.isEmpty)
    #expect(await probe.calls < 100)
}

@MainActor @Test func longOperationKeepsItsCredentialSnapshotAcrossSegments() async throws {
    @MainActor final class Secret { var value = "synthetic-original" }
    actor ObservedKeys {
        var values: [String] = []
        func add(_ value: String) { values.append(value) }
    }
    let secret = Secret(), observed = ObservedKeys()
    let runner = DefaultOperationRunner(apiKey: { secret.value }, isAllowed: { true }, streamAI: { _, _, key, _, _ in
        await observed.add(key)
        await MainActor.run { secret.value = "synthetic-replacement" }
        return "Synthetic result"
    })
    for await event in runner.run(longRequest()) { if case .failed(let error) = event { throw error } }
    let used = await observed.values
    #expect(used.count == 4)
    #expect(used.allSatisfy { $0 == "synthetic-original" })
    for await event in runner.run(longRequest()) { if case .failed(let error) = event { throw error } }
    let next = await observed.values
    #expect(next.count == 8 && next.suffix(4).allSatisfy { $0 == "synthetic-replacement" })
}
