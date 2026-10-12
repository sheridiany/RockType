import AppKit
import SwiftUI
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor private final class T8SpeechDriver: SpeechDriving {
    let voices: [SystemSpeechVoice] = [.init(identifier: "synthetic-en", language: "en-US"), .init(identifier: "synthetic-zh", language: "zh-CN")]
    let defaultLanguage = "en-US"
    var texts: [String] = []
    var stops = 0
    func speak(_ text: String, voice: SystemSpeechVoice, request: UUID,
               report: @escaping @MainActor @Sendable (UUID, SpeechPlaybackEvent) -> Void) -> Bool {
        texts.append(text); report(request, .started); return true
    }
    func stop() { stops += 1 }
}
@MainActor private final class T8Runner: OperationRunner {
    var requests = 0
    func start() {}; func stop() {}; func cancel() {}
    func run(_ request: OperationRequest) -> AsyncStream<OperationEvent> { requests += 1; return AsyncStream { _ in } }
}
private actor T8Dictionary {
    var pending: [String: CheckedContinuation<String?, Never>] = [:]
    func lookup(_ text: String) async -> String? { await withCheckedContinuation { pending[text] = $0 } }
    func contains(_ text: String) -> Bool { pending[text] != nil }
    func reply(_ text: String, _ value: String?) { pending.removeValue(forKey: text)?.resume(returning: value) }
}

@Suite(.serialized) @MainActor struct T8TranslationComponentsTests {
    private func request(_ text: String = "clarity") -> OperationRequest {
        .init(session: .init(snapshot: .init(text: text, source: .init(pid: 0, applicationName: "Synthetic"), method: .paste)), template: .defaults[0], settings: .defaults)
    }
    private func settle(_ predicate: () async -> Bool) async throws {
        for _ in 0..<1000 { if await predicate() { return }; await Task.yield() }
        try #require(await predicate())
    }
    @Test func dictionaryDoesNotBlockTranslationAndRejectsStaleMissingAndProtectedResults() async throws {
        let dictionary = T8Dictionary(), runner = T8Runner()
        var allowed = true
        let state = TranslateWindowState(request: request(), runner: runner, settings: { .defaults }, allowed: { allowed },
            wordLookup: WordLookup(allowed: { allowed }, provider: { await dictionary.lookup($0) }))
        defer { state.stop() }
        state.start()
        #expect(runner.requests == 1)
        try await settle { await dictionary.contains("clarity") }
        state.edit("focus", composing: true)
        #expect(state.definition == nil && runner.requests == 1)
        state.edit("focus"); state.submit()
        try await settle { await dictionary.contains("focus") }
        await dictionary.reply("focus", "focus noun synthetic current meaning")
        try await settle { state.definition?.term == "focus" }
        await dictionary.reply("clarity", "clarity noun synthetic stale meaning")
        for _ in 0..<20 { await Task.yield() }
        #expect(state.definition?.term == "focus")
        state.edit("missing"); state.submit()
        #expect(state.definition == nil)
        try await settle { await dictionary.contains("missing") }
        await dictionary.reply("missing", nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(state.definition == nil)
        state.edit("protected"); state.submit()
        try await settle { await dictionary.contains("protected") }
        allowed = false
        await dictionary.reply("protected", "protected noun synthetic meaning")
        for _ in 0..<20 { await Task.yield() }
        #expect(state.definition == nil)
    }
    @Test func windowCloseStopsBothSpeakersAndDiscardsPendingLookup() async throws {
        let dictionary = T8Dictionary(), source = T8SpeechDriver(), translation = T8SpeechDriver()
        let controller = TranslateWindowController(request: request(), runner: T8Runner(), settings: { .defaults }, allowed: { true }, defaults: nil,
            wordLookup: WordLookup(allowed: { true }, provider: { await dictionary.lookup($0) }),
            sourceSpeaker: TextSpeaker(driver: source, allowed: { true }), translationSpeaker: TextSpeaker(driver: translation, allowed: { true }))
        controller.show(source: nil, anchor: nil)
        try await settle { await dictionary.contains("clarity") }
        controller.state.sourceSpeaker.speak("clarity")
        #expect(controller.state.sourceSpeaker.isSpeaking)
        controller.state.translationSpeaker.speak("合成译文")
        #expect(!controller.state.sourceSpeaker.isActive && controller.state.translationSpeaker.isSpeaking)
        controller.close()
        #expect(!controller.state.sourceSpeaker.isActive && !controller.state.translationSpeaker.isActive)
        #expect(source.stops > 0 && translation.stops > 0)
        await dictionary.reply("clarity", "clarity noun synthetic late meaning")
        for _ in 0..<20 { await Task.yield() }
        #expect(controller.state.definition == nil && controller.state.original.isEmpty)
    }
    @Test func editsStopSpeechAndSentencesDoNotQueryDictionary() async {
        let source = T8SpeechDriver(), translation = T8SpeechDriver()
        let state = TranslateWindowState(request: request("This is a synthetic sentence."), runner: T8Runner(), settings: { .defaults }, allowed: { true },
            wordLookup: WordLookup(allowed: { true }, provider: { _ in Issue.record("Sentence queried dictionary"); return nil }),
            sourceSpeaker: TextSpeaker(driver: source, allowed: { true }), translationSpeaker: TextSpeaker(driver: translation, allowed: { true }))
        defer { state.stop() }
        state.start()
        state.sourceSpeaker.speak(state.original)
        state.edit("Another synthetic sentence here.")
        #expect(!state.sourceSpeaker.isActive)
        state.translationSpeaker.speak("合成译文")
        state.submit()
        #expect(!state.translationSpeaker.isActive && state.definition == nil)
        for _ in 0..<20 { await Task.yield() }
    }
    @Test func renderIntegratedDictionaryAndNoMatchInBothThemes() async throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/t8")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for dark in [false, true] {
            for matches in [false, true] {
                let request = request(matches ? "clarity" : "A complete synthetic sentence.")
                let source = T8SpeechDriver(), translation = T8SpeechDriver()
                let state = TranslateWindowState(request: request, runner: T8Runner(), settings: { .defaults }, allowed: { true },
                    wordLookup: WordLookup(allowed: { true }, provider: { _ in "clarity /ˈklærəti/ noun 合成释义：清楚、易于理解的表达。" }),
                    sourceSpeaker: TextSpeaker(driver: source, allowed: { true }), translationSpeaker: TextSpeaker(driver: translation, allowed: { true }))
                state.showCompleted(.init(session: request.session, templateID: "translate", text: matches ? "清晰；清楚。" : "一个完整的合成句子。", engine: "Apple Translation"))
                if matches { try await settle { state.definition != nil } }
                let hosting = NSHostingView(rootView: TranslateWindowView(state: state, close: {}, focusEditor: {}, copy: { _, _ in })
                    .environment(\.colorScheme, dark ? .dark : .light).frame(width: 420, height: 560))
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 560), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = hosting
                hosting.layoutSubtreeIfNeeded(); hosting.displayIfNeeded()
                let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)); hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("translate-\(matches ? "dictionary" : "sentence")-\(dark ? "dark" : "light").png"))
                window.close(); state.stop()
            }
        }
    }
}
