import Foundation
import Testing
@testable import RoarkTCore

private func t7Request(_ text: String = "Read `value()` at https://example.invalid/a?q=1.", target: String = "zh-Hans", model: String = "synthetic", prompt: String? = nil) -> OperationRequest {
    var settings = AppSettings.defaults
    settings.translation.engine = .ai; settings.translation.targetLanguage = target
    settings.ai.baseURL = "https://example.invalid/v1"; settings.ai.defaultModel = model
    var template = OperationTemplate.defaults.first { $0.id == "translate" }!
    if let prompt { template.prompt = prompt }
    return .init(session: .init(snapshot: .init(text: text, source: .init(pid: 0, applicationName: "Synthetic"), method: .paste)), template: template, settings: settings)
}
@MainActor private func t7Collect(_ runner: DefaultOperationRunner, _ request: OperationRequest) async -> [OperationEvent] {
    var events: [OperationEvent] = []
    for await event in runner.run(request) { events.append(event) }
    return events
}
private actor T7Echo {
    var calls = 0
    var leakedLiteral = false
    func respond(_ prompt: String, delta: @Sendable (String) async -> Void) async -> String {
        calls += 1
        leakedLiteral = prompt.contains("value()") || prompt.contains("https://example.invalid/a")
        let body = String(prompt.components(separatedBy: "<content>\n").last!.components(separatedBy: "\n</content>").first!)
        for character in body { await delta(String(character)) }
        return body
    }
}

@Test func t7ProtectionRoundTripsFencesInlineURLsAndUnicodeAcrossEveryCharacter() throws {
    let input = "说明😀 `value()` and ``a`b`` https://example.invalid/a_(b)?q=1。\r\n~~~swift\r\nlet x = `raw`\r\n~~~\r\nDone"
    let protected = try TranslationProtection(input)
    #expect(!protected.text.contains("value()") && !protected.text.contains("let x"))
    #expect(try protected.restore(protected.text) == input)
    var stream = TranslationProtection.Stream(protection: protected)
    var output = ""
    for character in protected.text { output += try stream.append(String(character)) }
    #expect(output == input)
    #expect(throws: (any Error).self) { try protected.restore("missing markers") }
    let marker = try #require(protected.literals.keys.first)
    #expect(throws: (any Error).self) { try protected.restore(protected.text + marker) }
    #expect(throws: (any Error).self) { try protected.restore(protected.text + protected.prefix + "999⟧") }
    var malformed = TranslationProtection.Stream(protection: protected)
    #expect(throws: (any Error).self) { try malformed.append(protected.prefix + String(repeating: "x", count: 1000)) }
    let indented = try TranslationProtection("Code:\n    let answer = 42\n\treturn answer\n")
    #expect(!indented.text.contains("let answer"))
    #expect(try indented.restore(indented.text) == "Code:\n    let answer = 42\n\treturn answer\n")
    let unclosed = "text\n```swift\nprivate code"
    let tail = try TranslationProtection(unclosed)
    #expect(try tail.restore(tail.text) == unclosed)
}

@Test @MainActor func t7CacheSeparatesRoutesPromptsAndLanguagesAndNeverStreamsMarkers() async {
    let echo = T7Echo(), cache = TranslationResultCache()
    let runner = DefaultOperationRunner(apiKey: { "synthetic" }, isAllowed: { true },
        streamAI: { _, prompt, _, _, delta in await echo.respond(prompt, delta: delta) }, translationCache: cache)
    for request in [t7Request(), t7Request(), t7Request(target: "fr"), t7Request(model: "other"), t7Request(prompt: "Translate to {{target}} accurately")] {
        let events = await t7Collect(runner, request)
        let output = events.compactMap { event -> String? in if case .delta(let s) = event { return s }; return nil }.joined()
        #expect(output == request.session.snapshot.text)
        #expect(events.contains { if case .completed = $0 { true } else { false } })
    }
    #expect(await echo.calls == 4)
    #expect(await !echo.leakedLiteral)
}

@Test @MainActor func t7LRUTTLAndSizeBounds() throws {
    var now = 0.0
    let cache = TranslationResultCache(capacity: 2, lifetime: 10, clock: { now })
    func key(_ text: String) throws -> TranslationResultCache.Key {
        try #require(cache.key(t7Request(text), target: "zh-Hans", engine: "ai", model: "synthetic"))
    }
    let a = try key("a"), b = try key("b"), c = try key("c")
    cache.insert("A", for: a); cache.insert("B", for: b)
    #expect(cache.value(for: a) == "A")
    cache.insert("C", for: c)
    #expect(cache.value(for: b) == nil)
    now = 11; #expect(cache.value(for: a) == nil)
    #expect(cache.key(t7Request(String(repeating: "x", count: 501)), target: "zh", engine: "ai", model: "x") == nil)
    #expect(cache.key(t7Request(String(repeating: "x", count: 500)), target: "zh", engine: "ai", model: "x") != nil)
    let tiny = TranslationResultCache(byteLimit: 1)
    tiny.insert("A", for: a); #expect(tiny.value(for: a) == nil)
}

@Test @MainActor func t7ProtectedInputRejectsHitsAndDoesNotRetainResult() async {
    var allowed = true
    let echo = T7Echo(), cache = TranslationResultCache()
    let runner = DefaultOperationRunner(apiKey: { "synthetic" }, isAllowed: { allowed },
        streamAI: { _, prompt, _, _, delta in await echo.respond(prompt, delta: delta) }, translationCache: cache)
    _ = await t7Collect(runner, t7Request())
    allowed = false
    let blocked = await t7Collect(runner, t7Request())
    #expect(blocked.contains(.failed(.protectedInput)))
    allowed = true
    _ = await t7Collect(runner, t7Request())
    #expect(await echo.calls == 2)
}

@Test @MainActor func t7MissingPlaceholdersCannotCompleteOrEnterCache() async {
    let runner = DefaultOperationRunner(apiKey: { "synthetic" }, isAllowed: { true },
        streamAI: { _, _, _, _, delta in await delta("Missing placeholders"); return "Missing placeholders" }, translationCache: TranslationResultCache())
    let events = await t7Collect(runner, t7Request())
    #expect(events.contains(.failed(.unavailable)))
    #expect(!events.contains { if case .completed = $0 { true } else { false } })
}

@MainActor private final class T7Offline: TextTranslationClient {
    var calls = 0
    var afterRead: () -> Void = {}
    func translate(sessionID: UUID, generation: UInt64, text: String, target: String) async throws -> String {
        calls += 1; afterRead(); return "Synthetic offline translation"
    }
    func cancel(sessionID: UUID, throughGeneration: UInt64) {}
    func stop() {}
}
@Test @MainActor func t7AppleCacheAndProtectionAtCompletion() async {
    let offline = T7Offline(), cache = TranslationResultCache()
    var allowed = true
    var settings = t7Request("short sentence").settings; settings.translation.engine = .offlineFirst
    let request = OperationRequest(session: t7Request("short sentence").session,
        template: t7Request().template, settings: settings)
    let runner = DefaultOperationRunner(offline: offline, apiKey: { "synthetic" }, isAllowed: { allowed }, translationCache: cache)
    var engines: [DefaultOperationRunner.LatencyEngine] = []
    runner.onFirstText = { engines.append($0.engine) }
    _ = await t7Collect(runner, request); _ = await t7Collect(runner, request)
    #expect(offline.calls == 1); #expect(engines == [.apple, .cache])
    cache.clear(); offline.afterRead = { allowed = false }
    let rejected = await t7Collect(runner, request)
    #expect(rejected.contains(.failed(.protectedInput)))
    allowed = true; offline.afterRead = {}
    _ = await t7Collect(runner, request)
    #expect(offline.calls == 3)
}
@Test @MainActor func t7CancelledTransportCannotFillCache() async {
    let cache = TranslationResultCache()
    let runner = DefaultOperationRunner(apiKey: { "synthetic" }, isAllowed: { true },
        streamAI: { _, _, _, _, _ in try await Task.sleep(for: .seconds(10)); return "late" }, translationCache: cache)
    let stream = runner.run(t7Request("short sentence"))
    await Task.yield(); runner.cancel()
    var events: [OperationEvent] = []
    for await event in stream { events.append(event) }
    #expect(events.contains(.cancelled))
    let key = cache.key(t7Request("short sentence"), target: "zh-Hans", engine: "ai", model: "synthetic", connection: t7Request().settings.ai)!
    #expect(cache.value(for: key) == nil)
}

@Test func t7LongPlainTokenDoesNotStallProtection() throws {
    for source in [String(repeating: "a", count: 16_000), "https://example.invalid/a" + String(repeating: ")", count: 16_000)] {
        let start = ContinuousClock.now
        let protected = try TranslationProtection(source)
        let elapsed = start.duration(to: .now)
        print("t7_protection_16000_ascii \(elapsed)")
        #expect(try protected.restore(protected.text) == source)
        #expect(elapsed < .milliseconds(200), "Long plain tokens must not trigger quadratic URL matching")
    }
}
