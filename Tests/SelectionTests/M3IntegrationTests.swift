import AppKit
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor private final class IntegrationRunner: OperationRunner {
    var requests: [OperationRequest] = []
    var streams: [AsyncStream<OperationEvent>.Continuation] = []
    var stops = 0
    func start() {}
    func stop() { stops += 1 }
    func cancel() {}
    func run(_ request: OperationRequest) -> AsyncStream<OperationEvent> {
        requests.append(request)
        return AsyncStream { streams.append($0) }
    }
    func complete(_ index: Int, text: String = "Synthetic answer") -> OperationResult {
        let request = requests[index]
        let session = OperationSession(id: request.session.id, snapshot: request.session.snapshot,
            turns: request.session.turns + [.init(question: request.question ?? "", answer: text)])
        let result = OperationResult(session: session, templateID: request.template.id, text: text, engine: "Synthetic model")
        streams[index].yield(.completed(result))
        return result
    }
}

@Suite(.serialized) @MainActor struct M3IntegrationTests {
    @Test func toolbarStreamsIntoWindowAndRecentResultsWithFollowUpAndPrivacy() async throws {
        _ = NSApplication.shared
        var settings = AppSettings.defaults
        var configured = true
        var readable = true
        var notices: [String] = []
        var runners: [IntegrationRunner] = []
        let environment = OperationsEnvironment()
        environment.start()
        let operations = SelectionOperationsController(environment: environment, settings: { settings },
            aiConfigured: { configured }, notice: { notices.append($0) }, readable: { readable }, makeRunner: {
                let runner = IntegrationRunner(); runners.append(runner); return runner
            })
        defer { operations.stop(); environment.stop() }
        let selection = SelectionController(settings: { settings },
            perform: { operations.perform($0, source: $1, toolbarRect: $2) },
            search: { _, _ in }, notice: { notices.append($0) },
            aiConfigured: { configured }, allowed: { readable })
        let captured = CapturedSelection(snapshot: .init(text: "Synthetic selection",
            source: .init(pid: 42, bundleID: "test.editor", applicationName: "Test"), method: .accessibility), isCurrent: { true })
        selection.performAction("summarize", captured: captured, fromToolbar: true)
        let first = try #require(runners.first)
        let window = try #require(operations.window)
        #expect(window.isVisible && first.requests.count == 1)
        first.streams[0].yield(.delta("Synthetic partial"))
        await settle()
        #expect(window.state.answer == "Synthetic partial" && window.state.phase == .streaming)
        let result = first.complete(0)
        await settle()
        #expect(window.state.phase == .done && environment.recent.results == [result])
        settings.selection.assistantModel = "new-model"
        operations.settingsChanged()
        window.state.question = "Synthetic follow-up"
        window.ask()
        #expect(first.requests[1].session == result.session)
        #expect(first.requests[1].settings.selection.assistantModel == "new-model")
        settings.privacy.keepRecentResultsInMemory = false
        operations.settingsChanged()
        _ = first.complete(1)
        await settle()
        #expect(environment.recent.results.isEmpty)
        settings.privacy.keepRecentResultsInMemory = true
        window.state.question = "Synthetic second follow-up"; window.ask()
        let latest = first.complete(2)
        await settle()
        #expect(environment.recent.results == [latest])
        operations.reopen(latest)
        #expect(first.stops > 0 && runners.count == 2 && runners[1].requests.isEmpty)
        #expect(operations.window?.state.session == latest.session && operations.window?.state.answer == latest.text)
        operations.clearCurrentContent()
        #expect(operations.window == nil && environment.recent.results.isEmpty)
        first.streams[2].yield(.delta("late"))
        await settle()
        #expect(environment.recent.results.isEmpty)

        configured = false
        selection.performAction("summarize", captured: captured, fromToolbar: true)
        #expect(runners.count == 2 && notices.last?.contains("设置") == true)
        let actions = SelectionToolbarAction.configured(in: settings, aiConfigured: false)
        #expect(actions.first { $0.id == "translate" }?.enabled == true)
        #expect(actions.filter { ["explain", "summarize", "polish"].contains($0.id) }.allSatisfy { !$0.enabled })
        settings.translation.engine = .ai
        selection.performAction("translate", captured: captured, fromToolbar: true)
        #expect(runners.count == 3 && runners[2].requests[0].settings.translation.engine == .offlineFirst)
        runners[2].streams[0].yield(.failed(.unavailable))
        await settle()
        #expect(notices.last?.contains("服务") == true)
        readable = false
        selection.performAction("translate", captured: captured, fromToolbar: true)
        #expect(runners.count == 3)
    }

    private func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }
}
