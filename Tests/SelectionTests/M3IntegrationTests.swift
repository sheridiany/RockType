import AppKit
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor private final class IntegrationRunner: OperationRunner {
    var requests: [OperationRequest] = []
    var streams: [AsyncStream<OperationEvent>.Continuation] = []
    var stops = 0
    private let completionDelay: Duration
    private var deliveries: [Task<Void, Never>] = []
    init(completionDelay: Duration) { self.completionDelay = completionDelay }
    func start() {}
    func stop() {
        stops += 1
        deliveries.forEach { $0.cancel() }
        deliveries.removeAll()
    }
    func cancel() {}
    func run(_ request: OperationRequest) -> AsyncStream<OperationEvent> {
        requests.append(request)
        return AsyncStream { streams.append($0) }
    }
    func complete(_ index: Int, text: String = "Synthetic answer") throws -> OperationResult {
        try #require(requests.indices.contains(index) && streams.indices.contains(index),
                     "A request and its event stream must exist before completing it")
        let request = requests[index]
        let session = OperationSession(id: request.session.id, snapshot: request.session.snapshot,
            turns: request.session.turns + [.init(question: request.question ?? "", answer: text)])
        let result = OperationResult(session: session, templateID: request.template.id, text: text, engine: "Synthetic model")
        let stream = streams[index]
        if completionDelay == .zero {
            stream.yield(.completed(result))
        } else {
            deliveries.append(Task { @MainActor [completionDelay] in
                do { try await Task.sleep(for: completionDelay) } catch { return }
                stream.yield(.completed(result))
            })
        }
        return result
    }
}

@Suite(.serialized) @MainActor struct M3IntegrationTests {
    // A delayed completion reproduces the former fixed-yield race deterministically.
    @Test(arguments: [Duration.zero, .milliseconds(25)])
    func toolbarStreamsIntoWindowAndRecentResultsWithFollowUpAndPrivacy(completionDelay: Duration) async throws {
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
                let runner = IntegrationRunner(completionDelay: completionDelay); runners.append(runner); return runner
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
        try #require(window.isVisible && first.requests.count == 1 && first.streams.count == 1)
        first.streams[0].yield(.delta("Synthetic partial"))
        try await waitFor("Partial answer is consumed") {
            window.state.answer == "Synthetic partial" && window.state.phase == .streaming
        }
        let result = try first.complete(0)
        try await waitFor("Completion is consumed before asking a follow-up") {
            window.state.phase == .done && environment.recent.results == [result]
        }
        settings.selection.assistantModel = "new-model"
        operations.settingsChanged()
        window.state.question = "Synthetic follow-up"
        window.ask()
        try #require(first.requests.count == 2 && first.streams.count == 2)
        #expect(first.requests[1].session == result.session)
        #expect(first.requests[1].settings.selection.assistantModel == "new-model")
        settings.privacy.keepRecentResultsInMemory = false
        operations.settingsChanged()
        let privateResult = try first.complete(1)
        try await waitFor("Private completion is consumed without adding recent results") {
            window.state.phase == .done && window.state.session == privateResult.session
                && environment.recent.results.isEmpty
        }
        settings.privacy.keepRecentResultsInMemory = true
        window.state.question = "Synthetic second follow-up"; window.ask()
        try #require(first.requests.count == 3 && first.streams.count == 3)
        let latest = try first.complete(2)
        try await waitFor("Second follow-up reaches recent results") {
            window.state.phase == .done && environment.recent.results == [latest]
        }
        operations.reopen(latest)
        try #require(first.stops > 0 && runners.count == 2)
        #expect(runners[1].requests.isEmpty)
        #expect(operations.window?.state.session == latest.session && operations.window?.state.answer == latest.text)
        operations.clearCurrentContent()
        #expect(operations.window == nil && environment.recent.results.isEmpty)
        // The completed stream has no consumer; asserting termination avoids
        // a timed negative assertion that could pass before a late event runs.
        if case .terminated = first.streams[2].yield(.delta("late")) {} else {
            Issue.record("Completed event stream must reject late events")
        }
        #expect(environment.recent.results.isEmpty)

        configured = false
        selection.performAction("summarize", captured: captured, fromToolbar: true)
        #expect(runners.count == 2 && notices.last?.contains("设置") == true)
        let actions = SelectionToolbarAction.configured(in: settings, aiConfigured: false)
        #expect(actions.first { $0.id == "translate" }?.enabled == true)
        #expect(actions.filter { ["explain", "summarize", "polish"].contains($0.id) }.allSatisfy { !$0.enabled })
        settings.translation.engine = .ai
        selection.performAction("translate", captured: captured, fromToolbar: true)
        try #require(runners.count == 3)
        try #require(runners[2].requests.count == 1 && runners[2].streams.count == 1)
        #expect(runners[2].requests[0].settings.translation.engine == .offlineFirst)
        runners[2].streams[0].yield(.failed(.unavailable))
        try await waitFor("Failure feedback is consumed") {
            notices.last?.contains("服务") == true
        }
        readable = false
        selection.performAction("translate", captured: captured, fromToolbar: true)
        #expect(runners.count == 3)
    }

    private func waitFor(_ reason: String, condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        // Abort the test on timeout: a failed precondition must never flow into
        // a request-array subscript or another action requiring completed state.
        try #require(condition(), Comment(rawValue: reason))
    }
}
