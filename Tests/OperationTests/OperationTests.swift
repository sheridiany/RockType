import Foundation
import Testing
import RoarkTCore
@testable import RoarkTApp

private func snapshot() -> ContentSnapshot {
    ContentSnapshot(text: "Synthetic paragraph\n\n- synthetic item", source: .init(pid: 42,
        applicationName: "Synthetic"), method: .accessibility)
}
private func request(id: String = "summarize", engine: TranslationSettings.Engine = .offlineFirst,
                     question: String? = nil, session: OperationSession? = nil,
                     limit: Int = 16_384) -> OperationRequest {
    var settings = AppSettings()
    settings.ai.baseURL = "https://synthetic.invalid/v1"
    settings.ai.defaultModel = "default-model"
    settings.selection.assistantModel = "assistant-model"
    settings.translation.model = "translation-model"
    settings.translation.engine = engine
    return OperationRequest(session: session ?? OperationSession(snapshot: snapshot()),
        template: OperationTemplate.defaults.first { $0.id == id }!, settings: settings,
        question: question, maximumInputBytes: limit)
}
@MainActor private func collect(_ stream: AsyncStream<OperationEvent>) async -> [OperationEvent] {
    var events: [OperationEvent] = []
    for await event in stream { events.append(event) }
    return events
}
private func result(_ events: [OperationEvent]) -> OperationResult? {
    for event in events { if case .completed(let value) = event { return value } }
    return nil
}

private final class StreamStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!, cacheStoragePolicy: .notAllowed)
        for byte in "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"合成\"}}]}\n\ndata: [DONE]\n\n".utf8 {
            client?.urlProtocol(self, didLoad: Data([byte]))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test @MainActor func realAIClientStreamAndRecentResults() async {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StreamStub.self]
    let network = URLSession(configuration: config)
    defer { network.invalidateAndCancel() }
    let recent = InMemoryRecentResults()
    let runner = DefaultOperationRunner(recent: recent, apiKey: { "synthetic" }, isAllowed: { true },
        streamAI: { settings, text, key, model, delta in
            try await AIClient(connection: settings, session: network).stream(text: text, apiKey: key,
                model: model, onDelta: delta)
        })
    let events = await collect(runner.run(request()))
    #expect(events.contains(.delta("合成")))
    #expect(result(events)?.engine == "assistant-model")
    #expect(result(events)?.session.turns.count == 1)
    #expect(recent.results.count == 1)
    runner.stop(); recent.stop()
    #expect(recent.results.isEmpty)
}

@MainActor private final class Offline: TextTranslationClient {
    var calls = 0
    var fail = false
    var cancelled = false
    func translate(sessionID: UUID, generation: UInt64, text: String, target: String) async throws -> String {
        calls += 1
        if fail { throw OperationFailure.unavailable }
        return "Offline synthetic\n\n- item"
    }
    func cancel(sessionID: UUID, throughGeneration: UInt64) { cancelled = true }
    func stop() {}
}
private actor Recorder {
    var prompts: [String] = []
    var models: [String] = []
    func record(_ prompt: String, _ model: String) { prompts.append(prompt); models.append(model) }
}
@Test @MainActor func translationRoutesAndModelSelection() async {
    let offline = Offline()
    let log = Recorder()
    let runner = DefaultOperationRunner(offline: offline, apiKey: { "synthetic" }, isAllowed: { true },
        streamAI: { _, prompt, _, model, delta in
            await log.record(prompt, model); await delta("AI synthetic"); return "AI synthetic"
        })
    let first = await collect(runner.run(request(id: "translate")))
    #expect(result(first)?.engine == "Apple Translation")
    #expect(await log.models.isEmpty)
    offline.fail = true
    let fallback = await collect(runner.run(request(id: "translate")))
    #expect(result(fallback)?.engine == "translation-model")
    #expect(offline.calls == 2)
    let direct = await collect(runner.run(request(id: "translate", engine: .ai)))
    #expect(result(direct)?.engine == "translation-model")
    #expect(offline.calls == 2)
    #expect(await log.models == ["translation-model", "translation-model"])
}

@Test @MainActor func completedTurnsFollowupNewSessionAndPromptEdit() async throws {
    let log = Recorder()
    let runner = DefaultOperationRunner(apiKey: { "synthetic" }, isAllowed: { true },
        streamAI: { _, prompt, _, model, _ in
            await log.record(prompt, model); return "Completed synthetic answer"
        })
    let first = try #require(result(await collect(runner.run(request()))))
    let followup = request(question: "Synthetic follow-up", session: first.session)
    let second = try #require(result(await collect(runner.run(followup))))
    #expect(second.session.turns.count == 2)
    _ = await collect(runner.run(request()))
    let prompts = await log.prompts
    #expect(prompts[1].contains("Completed synthetic answer"))
    #expect(prompts[1].contains("Synthetic follow-up"))
    #expect(!prompts[2].contains("Completed synthetic answer"))
    var template = OperationTemplate.defaults[1]
    template.prompt = "Edited synthetic instruction"; template.model = "template-model"
    let edited = OperationRequest(session: first.session, template: template, settings: AppSettings())
    let fourth = await collect(runner.run(edited))
    #expect(result(fourth)?.engine == "template-model")
    #expect(await log.prompts.last?.hasPrefix(template.prompt) == true)
}

@Test @MainActor func limitsAndProtectionPreventAnyTransport() async {
    let log = Recorder()
    var allowed = true
    var keys = 0
    let offline = Offline()
    let runner = DefaultOperationRunner(offline: offline, apiKey: { keys += 1; return "synthetic" },
        isAllowed: { allowed }, streamAI: { _, prompt, _, model, _ in
            await log.record(prompt, model); return "unexpected"
        })
    #expect(await collect(runner.run(request(id: "translate", limit: 1))).contains(.failed(.inputTooLong(limit: 1))))
    allowed = false
    #expect(await collect(runner.run(request(id: "translate"))).contains(.failed(.protectedInput)))
    #expect(keys == 0)
    #expect(offline.calls == 0)
    #expect(await log.models.isEmpty)
}

/// Deliberately ignores cancellation until released, modelling a late callback.
private actor Gate {
    var callback: (@Sendable (String) async -> Void)?
    var waiter: CheckedContinuation<String, Never>?
    func wait(_ delta: @escaping @Sendable (String) async -> Void) async -> String {
        callback = delta
        return await withCheckedContinuation { waiter = $0 }
    }
    func ready() -> Bool { waiter != nil }
    func release() async { await callback?("Late synthetic"); waiter?.resume(returning: "Late synthetic"); waiter = nil }
}
@Test @MainActor func cancelAndSupersessionDiscardLateEvents() async {
    let gate = Gate()
    let recent = InMemoryRecentResults()
    let runner = DefaultOperationRunner(recent: recent, apiKey: { "synthetic" }, isAllowed: { true },
        streamAI: { _, _, _, model, delta in
            if model == "assistant-model" { return await gate.wait(delta) }
            await delta("New synthetic"); return "New synthetic"
        })
    let old = runner.run(request())
    while !(await gate.ready()) { await Task.yield() }
    let new = runner.run(request(id: "translate", engine: .ai))
    await gate.release()
    let oldEvents = await collect(old)
    #expect(oldEvents.last == .cancelled)
    #expect(!oldEvents.contains(.delta("Late synthetic")))
    #expect(result(await collect(new))?.text == "New synthetic")
    #expect(recent.results.count == 1)
    let pending = runner.run(request())
    while !(await gate.ready()) { await Task.yield() }
    runner.cancel(); await gate.release()
    #expect(await collect(pending).last == .cancelled)
    #expect(recent.results.count == 1)
}

@Test @MainActor func protectionChangeStopsSilentTransportAndNoCache() async {
    let gate = Gate()
    var allowed = true
    let recent = InMemoryRecentResults()
    let runner = DefaultOperationRunner(recent: recent, apiKey: { "synthetic" }, isAllowed: { allowed },
        streamAI: { _, _, _, _, delta in await gate.wait(delta) })
    let events = runner.run(request())
    while !(await gate.ready()) { await Task.yield() }
    allowed = false
    let received = await collect(events)
    #expect(received.last == .failed(.protectedInput))
    await gate.release()
    #expect(recent.results.isEmpty)
}

@Test @MainActor func recentCapacityClearAndDeduplication() {
    let recent = InMemoryRecentResults()
    for i in 0..<12 {
        recent.add(OperationResult(session: OperationSession(snapshot: snapshot()), templateID: "explain",
            text: "Synthetic \(i)", engine: "synthetic"))
    }
    #expect(recent.results.count == 10)
    #expect(recent.results.first?.text == "Synthetic 11")
    #expect(recent.results.last?.text == "Synthetic 2")
    recent.add(recent.results[0])
    #expect(recent.results.count == 10)
    recent.clear(); #expect(recent.results.isEmpty)
}

@Test func searchEncodesAndRejectsUnsafeTemplates() throws {
    let query = "中文 & + # / ? 😀"
    let url = try SearchURL.make(query: query, engine: "https://www.google.com/search?q={query}&hl=zh")
    let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(parts.queryItems?.first?.value == query)
    #expect(parts.queryItems?.count == 2)
    #expect(throws: OperationFailure.emptyInput) { try SearchURL.make(query: " \n", engine: "https://example.invalid/?q={query}") }
    for template in ["file:///tmp/{query}", "https://{query}.invalid/", "https://example.invalid/#?q={query}",
                     "https://example.invalid/?q={query}{query}"] {
        #expect(throws: OperationFailure.invalidSearchURL) { try SearchURL.make(query: "probe", engine: template) }
    }
}

private final class HangingStreamStub: URLProtocol, @unchecked Sendable {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var started = false
        var stopped = false
        func use<T>(_ body: (State) -> T) -> T { lock.lock(); defer { lock.unlock() }; return body(self) }
    }
    private static let state = State()
    static var started: Bool { state.use { $0.started } }
    static var stopped: Bool { state.use { $0.stopped } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.state.use { $0.started = true }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!, cacheStoragePolicy: .notAllowed)
    }
    override func stopLoading() { Self.state.use { $0.stopped = true } }
}
@Test @MainActor func runnerCancellationStopsURLSessionTransport() async throws {
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [HangingStreamStub.self]
    let network = URLSession(configuration: config)
    defer { network.invalidateAndCancel() }
    let runner = DefaultOperationRunner(apiKey: { "synthetic" }, isAllowed: { true },
        streamAI: { settings, text, key, model, delta in
            try await AIClient(connection: settings, session: network).stream(text: text, apiKey: key, model: model, onDelta: delta)
        })
    let events = runner.run(request())
    for _ in 0..<100 where !HangingStreamStub.started { try await Task.sleep(for: .milliseconds(5)) }
    #expect(HangingStreamStub.started)
    runner.cancel()
    #expect(await collect(events).last == .cancelled)
    for _ in 0..<100 where !HangingStreamStub.stopped { try await Task.sleep(for: .milliseconds(5)) }
    #expect(HangingStreamStub.stopped)
}

@Test @MainActor func modelErrorsAndDisabledHistoryDoNotSaveResults() async {
    let recent = InMemoryRecentResults()
    let runner = DefaultOperationRunner(recent: recent, apiKey: { "synthetic" }, isAllowed: { true },
        streamAI: { _, _, _, _, _ in throw AIClientError.unauthorized })
    #expect(await collect(runner.run(request())).last == .failed(.ai(.unauthorized)))
    #expect(recent.results.isEmpty)
    let successful = DefaultOperationRunner(recent: recent, apiKey: { "synthetic" }, isAllowed: { true },
        streamAI: { _, _, _, _, _ in "Synthetic answer" })
    var settings = AppSettings(); settings.privacy.keepRecentResultsInMemory = false
    let disabled = OperationRequest(session: OperationSession(snapshot: snapshot()),
        template: OperationTemplate.defaults[1], settings: settings)
    #expect(result(await collect(successful.run(disabled))) != nil)
    #expect(recent.results.isEmpty)
    var image = OperationTemplate.defaults[1]; image.input = .image
    let unsupported = OperationRequest(session: disabled.session, template: image, settings: settings)
    #expect(await collect(successful.run(unsupported)).last == .failed(.unsupportedInput))
}

@Test @MainActor func emptyCompletionCannotEnterHistory() async {
    let recent = InMemoryRecentResults()
    let runner = DefaultOperationRunner(recent: recent, apiKey: { "synthetic" }, isAllowed: { true },
        streamAI: { _, _, _, _, _ in " \n" })
    #expect(await collect(runner.run(request())).last == .failed(.unavailable))
    #expect(recent.results.isEmpty)
}
