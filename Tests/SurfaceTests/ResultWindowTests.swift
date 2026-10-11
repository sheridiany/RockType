import Foundation
import RoarkTCore
@testable import RoarkTApp
import SwiftUI
import AppKit
import Testing

/// Controllable event source for the production result-window state.
@MainActor private final class ControlledRunner: OperationRunner {
    var requests: [OperationRequest] = []
    var streams: [AsyncStream<OperationEvent>.Continuation] = []
    var cancellations = 0
    func start() {}
    func stop() { cancel() }
    func cancel() { cancellations += 1 }
    func run(_ request: OperationRequest) -> AsyncStream<OperationEvent> {
        requests.append(request)
        return AsyncStream { streams.append($0) }
    }
}

@MainActor private final class CheckContext { var readable = true; var saved: [OperationResult] = [] }

@Suite(.serialized) @MainActor struct ResultWindowTests {
    @Test func streamingAndSessionLifecycle() async {
        let runner = ControlledRunner()
        let context = CheckContext()
        let state = ResultWindowState(runner: runner, readable: { context.readable }, completed: { context.saved.append($0) })
        let snapshot = ContentSnapshot(text: "Synthetic input", source: .init(pid: 0, applicationName: "Test"), method: .paste)
        let session = OperationSession(snapshot: snapshot)
        let request = OperationRequest(session: session, template: .defaults[1], settings: .defaults)
        state.start(); state.show(request)
        runner.streams[0].yield(.delta("partial"))
        await settle()
        #expect(state.answer == "partial" && state.isBusy)
        state.cancel()
        runner.streams[0].yield(.delta("late"))
        runner.streams[0].yield(.completed(result(session)))
        await settle()
        #expect(state.answer == "partial" && state.phase == .cancelled && context.saved.isEmpty)

        state.show(request)
        runner.streams[1].yield(.delta("obsolete"))
        let fresh = OperationSession(snapshot: snapshot)
        state.show(OperationRequest(session: fresh, template: .defaults[1], settings: .defaults))
        runner.streams[1].yield(.completed(result(session)))
        runner.streams[2].yield(.engine("synthetic"))
        runner.streams[2].yield(.completed(result(fresh)))
        await settle()
        #expect(state.answer == "answer" && state.phase == .done && context.saved.count == 1)
        #expect(state.session?.id == fresh.id)

        state.question = "follow up"
        state.ask(settings: .defaults)
        #expect(runner.requests.last?.session.turns == [OperationTurn(question: "", answer: "answer")])
        #expect(runner.requests.last?.question == "follow up")
        runner.streams[3].yield(.delta("unfinished"))
        await settle(); state.cancel()
        state.question = "another question"; state.ask(settings: .defaults)
        #expect(runner.requests.last?.session.turns.count == 1) // cancelled answer is not context
        runner.streams[4].yield(.failed(.inputTooLong(limit: 10)))
        await settle()
        #expect(state.phase == .failed && state.notice?.contains("10") == true)

        let count = runner.requests.count
        context.readable = false; state.retry(settings: .defaults)
        #expect(runner.requests.count == count && state.phase == .failed)
        context.readable = true; state.retry(settings: .defaults)
        context.readable = false
        runner.streams[5].yield(.completed(result(fresh)))
        await settle()
        #expect(context.saved.count == 1 && state.answer.isEmpty && state.phase == .failed)

        context.readable = true; state.show(request)
        runner.streams[6].finish()
        await settle()
        #expect(state.phase == .failed) // EOF without terminal event is incomplete
        state.show(request)
        runner.streams[7].yield(.completed(result(fresh)))
        await settle()
        #expect(state.phase == .failed && context.saved.count == 1) // wrong session
        state.show(request)
        #expect(state.session?.turns.isEmpty == true && state.history.isEmpty)
        state.stop()
        runner.streams[8].yield(.delta("after close"))
        await settle()
        #expect(state.answer.isEmpty && state.session == nil && state.phase == .idle)
        state.show(result(fresh), template: .defaults[1], settings: .defaults)
        state.retry(settings: .defaults)
        #expect(runner.requests.last?.session.turns.isEmpty == true)
        #expect(runner.requests.last?.question == nil) // retry reopened result must not duplicate its answer
        state.stop()
    }
        @Test func renderLiveSurface() throws {
        _ = NSApplication.shared
        let controller = ResultWindowController(runner: ControlledRunner(), settings: { .defaults }, feedback: { _ in })
        let snapshot = ContentSnapshot(text: "This is synthetic preview content.\nA second paragraph preserves spacing.",
                                       source: .init(pid: 0, applicationName: "Preview"), method: .screenshotOCR)
        let session = OperationSession(snapshot: snapshot,
                                       turns: [.init(question: "", answer: "这是用于界面检查的合成内容。\n\n• 保留段落与列表\n• 复制后自行粘贴")])
        let result = OperationResult(session: session, templateID: "summarize", text: session.turns[0].answer, engine: "Preview model")
        for dark in [false, true] {
            for expanded in [false, true] {
                controller.state.show(result, template: .defaults[1], settings: .defaults)
                controller.state.sourceExpanded = expanded
                controller.state.asking = expanded
                let view = LiveResultWindowView(controller: controller)
                    .frame(width: 420, height: 480).environment(\.colorScheme, dark ? .dark : .light)
                let hosting = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 480),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = hosting
                hosting.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                hosting.displayIfNeeded()
                guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                    fatalError("Live surface bitmap failed")
                }
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else {
                    fatalError("Live surface rendering failed")
                }
                window.close()
                let path = "/tmp/roarkt-result-\(dark ? "dark" : "light")-\(expanded ? "expanded" : "done").png"
                try data.write(to: URL(fileURLWithPath: path))
            }
        }
        controller.stop()
    }
        private func result(_ session: OperationSession) -> OperationResult {
        OperationResult(session: OperationSession(id: session.id, snapshot: session.snapshot,
                                                  turns: session.turns + [.init(question: "", answer: "answer")]),
                        templateID: "summarize", text: "answer", engine: "synthetic")
    }
    private func settle() async { try? await Task.sleep(for: .milliseconds(30)) }
}
