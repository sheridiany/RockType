import AppKit
import SwiftUI
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor private final class TranslateTestRunner: OperationRunner {
    var requests: [OperationRequest] = []
    var streams: [AsyncStream<OperationEvent>.Continuation] = []
    var cancellations = 0
    func start() {}
    func stop() { cancel() }
    func cancel() { cancellations += 1 }
    func run(_ request: OperationRequest) -> AsyncStream<OperationEvent> {
        requests.append(request)
        let (stream, continuation) = AsyncStream<OperationEvent>.makeStream(); streams.append(continuation)
        return stream
    }
    func finish(_ index: Int, answer: String = "合成译文") {
        let request = requests[index]
        let session = OperationSession(id: request.session.id, snapshot: request.session.snapshot,
            turns: request.session.turns + [.init(question: request.question ?? "", answer: answer)])
        streams[index].yield(.completed(.init(session: session, templateID: request.template.id, text: answer, engine: "synthetic-model")))
        streams[index].finish()
    }
}

@Suite(.serialized) @MainActor struct TranslateWindowTests {
    private func request(_ text: String = "Synthetic source") -> OperationRequest {
        .init(session: .init(snapshot: .init(text: text, source: .init(pid: 0, applicationName: "Synthetic"), method: .paste)), template: OperationTemplate.defaults[0], settings: .defaults)
    }
    @Test func editsDebounceCompositionAndDiscardOldReplies() async throws {
        let runner = TranslateTestRunner()
        let state = TranslateWindowState(request: request(), runner: runner, settings: { .defaults }, allowed: { true })
        state.start(); defer { state.stop() }
        state.edit("first edit"); state.edit("最终原文", composing: true)
        runner.finish(0, answer: "stale")
        try await Task.sleep(for: .milliseconds(560))
        #expect(runner.requests.count == 1 && state.result.answer.isEmpty)
        state.edit("最终原文")
        try await Task.sleep(for: .milliseconds(560))
        #expect(runner.requests.count == 2)
        #expect(runner.requests.last?.session.snapshot.text == "最终原文")
        #expect(runner.requests[0].session.id != runner.requests[1].session.id)
        state.edit("Return immediately"); state.submit()
        #expect(runner.requests.count == 3)
        try await Task.sleep(for: .milliseconds(560))
        #expect(runner.requests.count == 3)
    }
    @Test func languageEngineSwapAndProtectionKeepWindowStateIsolated() async throws {
        let runner = TranslateTestRunner(); var saved: [String] = []; var allowed = true
        let global = AppSettings.defaults
        let state = TranslateWindowState(request: request(), runner: runner, settings: { global }, rememberTarget: { saved.append($0) }, allowed: { allowed })
        state.start(); defer { state.stop() }
        state.chooseTarget("ja"); state.chooseSource("en")
        #expect(saved == ["ja"] && state.engine == .ai)
        #expect(runner.requests.last?.template.prompt.contains("原文语言：英语") == true)
        #expect(runner.requests.last?.settings.translation.targetLanguage == "ja")
        runner.finish(runner.requests.count - 1, answer: "翻訳")
        for _ in 0..<20 where state.result.phase != .done { await Task.yield() }
        state.swap()
        #expect(state.original == "翻訳" && state.targetLanguage == "en" && state.sourceLanguage == "ja")
        state.chooseEngine(.offlineFirst)
        #expect(state.sourceLanguage == "auto" && global.translation.engine == .offlineFirst)
        let count = runner.requests.count
        allowed = false; state.edit("protected"); state.submit()
        try await Task.sleep(for: .milliseconds(560))
        #expect(runner.requests.count == count && state.result.answer.isEmpty)
    }
    @Test func customTranslationRoutingAndWindowBounds() {
        #expect(TranslateWindowState.accepts(OperationTemplate.defaults[0]))
        #expect(!TranslateWindowState.accepts(OperationTemplate.defaults[2]))
        #expect(TranslateWindowState.accepts(.init(name: "Synthetic translation", icon: "sparkles", prompt: "Translate into {{target}}")))
        #expect(!TranslateWindowState.accepts(.init(name: "Synthetic image", icon: "photo", prompt: "{{target}}", input: .image)))
        let screen = CGRect(x: 0, y: 0, width: 1280, height: 800)
        #expect(TranslateWindowController.fittedSize(.init(width: 420, height: 900), screen: screen) == CGSize(width: 420, height: 480))
    }
    @Test func productionDispatchSeparatesTranslationAndGeneralResults() throws {
        let environment = OperationsEnvironment(); environment.start()
        let operations = SelectionOperationsController(environment: environment, settings: { .defaults }, aiConfigured: { true }, notice: { _ in }, readable: { true }, makeRunner: { TranslateTestRunner() })
        defer { operations.stop(); environment.stop() }
        operations.perform(request(), source: nil, toolbarRect: nil)
        #expect(operations.translationWindow?.isVisible == true && operations.window == nil)
        let base = request()
        operations.perform(.init(session: base.session, template: OperationTemplate.defaults[2], settings: .defaults), source: nil, toolbarRect: nil)
        #expect(operations.window?.isVisible == true)
    }
    @Test func renderTranslationThemesAndStates() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/t1")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for dark in [false, true] {
            for mode in ["ready", "empty", "error"] {
                let request = request(mode == "empty" ? "" : "Keep the operation cancellable.\nPreserve `request_id` and the original formatting.")
                let state = TranslateWindowState(request: request, runner: TranslateTestRunner(), settings: { .defaults }, allowed: { true })
                if mode == "ready" {
                    state.showCompleted(.init(session: .init(snapshot: request.session.snapshot, turns: [.init(question: "", answer: "保持操作可取消。\n保留 `request_id` 和原有格式。")]), templateID: "translate", text: "保持操作可取消。\n保留 `request_id` 和原有格式。", engine: "Apple Translation"))
                } else if mode == "error" { state.result.notice = "连接未完成，请检查网络后重试。" }
                let view = TranslateWindowView(state: state, close: {}, focusEditor: {}, copy: { _, _ in }).environment(\.colorScheme, dark ? .dark : .light).frame(width: 420, height: 420)
                let hosting = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 420), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = hosting
                hosting.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)); hosting.displayIfNeeded()
                let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)); hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("translate-\(mode)-\(dark ? "dark" : "light").png"))
                window.close(); state.stop()
            }
        }
    }
}
