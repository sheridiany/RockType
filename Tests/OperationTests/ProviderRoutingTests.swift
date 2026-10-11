import Foundation
import Testing
import RoarkTCore
@testable import RoarkTApp

private actor ProviderCalls {
    var values: [String] = []
    func add(_ value: String) { values.append(value) }
}
private func routedSettings() -> AppSettings {
    var settings = AppSettings()
    settings.ai.id = "primary"; settings.ai.defaultModel = "primary-model"
    settings.ai.baseURL = "https://primary.invalid/v1"
    var other = AIConnectionSettings()
    other.id = "other"; other.defaultModel = "other-default"; other.baseURL = "https://other.invalid/v1"
    other.fallbackModel = "explicit-backup"
    settings.aiProviders = [other]
    settings.aiTaskRoutes = [AITask.assistant.rawValue: .init(providerID: "other", model: "task-model")]
    return settings
}
private func providerRequest(_ settings: AppSettings) -> OperationRequest {
    .init(session: .init(snapshot: .init(text: "Synthetic input", source: .init(pid: 0, applicationName: "Test"), method: .paste)),
          template: .defaults[1], settings: settings)
}
@MainActor private func terminal(_ stream: AsyncStream<OperationEvent>) async -> [OperationEvent] {
    var values: [OperationEvent] = []
    for await event in stream { values.append(event) }
    return values
}

@Test @MainActor func taskRouteUsesItsOwnCredentialAndExplicitFallback() async {
    let calls = ProviderCalls()
    var accounts: [String] = []
    let runner = DefaultOperationRunner(apiKey: { "wrong-default-key" }, isAllowed: { true },
        streamAI: { connection, _, key, model, delta in
            await calls.add(connection.id + ":" + key + ":" + model)
            if model == "task-model" { throw AIClientError.server }
            await delta("Synthetic answer"); return "Synthetic answer"
        }, providerKey: { id in accounts.append(id); return "synthetic-" + id })
    defer { runner.stop() }
    let values = await terminal(runner.run(providerRequest(routedSettings())))
    #expect(accounts == ["other"])
    #expect(await calls.values == ["other:synthetic-other:task-model", "other:synthetic-other:explicit-backup"])
    #expect(values.contains(.engine("explicit-backup · 备用模型")))
    guard case .completed(let result) = values.last else { Issue.record("Expected a completed fallback"); return }
    #expect(result.engine == "explicit-backup · 备用模型" && result.session.turns.count == 1)
    #expect(result.session.turns.first?.question == "")
}

@Test @MainActor func partialOutputAndProtectedInputNeverFallBack() async {
    let calls = ProviderCalls()
    let runner = DefaultOperationRunner(apiKey: { "synthetic" }, isAllowed: { true }, streamAI: { _, _, _, model, delta in
        await calls.add(model); await delta("partial"); throw AIClientError.network
    })
    defer { runner.stop() }
    let values = await terminal(runner.run(providerRequest(routedSettings())))
    #expect(await calls.values == ["task-model"])
    #expect(values.last == .failed(.ai(.network)))
    var allowed = true
    let protected = DefaultOperationRunner(apiKey: { "synthetic" }, isAllowed: { allowed }, streamAI: { _, _, _, _, _ in
        await MainActor.run { allowed = false }
        throw AIClientError.server
    })
    let result = await terminal(protected.run(providerRequest(routedSettings())))
    #expect(result.last == .failed(.protectedInput))
    protected.stop()
}

@Test @MainActor func removedProviderFailsBeforeCredentialRead() async {
    var settings = routedSettings(); settings.aiProviders = []
    var reads = 0
    let runner = DefaultOperationRunner(apiKey: { reads += 1; return "synthetic" }, isAllowed: { true })
    let values = await terminal(runner.run(providerRequest(settings)))
    #expect(values.last == .failed(.ai(.configuration)) && reads == 0)
    runner.stop()
}

@Test func providerSettingsDecodeWithoutNewFieldsAndSwitchWithoutLosingProfiles() throws {
    var settings = routedSettings()
    AIProviderRouting.select("other", in: &settings)
    #expect(settings.ai.id == "other" && settings.aiProviders?.map(\.id) == ["primary"])
    #expect(try AIProviderRouting.resolve(settings, task: .assistant).model == "task-model")
    AIProviderRouting.select("primary", in: &settings)
    #expect(settings.aiProviders?.first?.fallbackModel == "explicit-backup")
    #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)) == settings)
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
    json.removeValue(forKey: "aiProviders"); json.removeValue(forKey: "aiTaskRoutes")
    var ai = try #require(json["ai"] as? [String: Any]); ai.removeValue(forKey: "fallbackModel"); json["ai"] = ai
    let old = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(old.aiProviders == nil && old.aiTaskRoutes == nil && old.ai.fallbackModel == nil)
}

@Test func imageTaskInheritsSelectedProvidersVisionModel() throws {
    var settings = routedSettings()
    settings.aiProviders?[0].visionModel = "provider-vision"
    settings.aiTaskRoutes?[AITask.image.rawValue] = .init(providerID: "other")
    #expect(try AIProviderRouting.resolve(settings, task: .image).model == "provider-vision")
    settings.aiTaskRoutes?[AITask.image.rawValue]?.model = "explicit-image"
    #expect(try AIProviderRouting.resolve(settings, task: .image).model == "explicit-image")
}

@Test func authenticationCancellationAndUnconfiguredBackupNeverFallback() {
    var connection = AIConnectionSettings(); connection.defaultModel = "main"
    #expect(AIProviderRouting.fallback(for: connection, primary: "main", error: AIClientError.server, hasVisibleOutput: false) == nil)
    connection.fallbackModel = AIProviderRouting.suggestedFallback
    for error: AIClientError in [.unauthorized, .cancelled, .configuration, .decoding, .outputLimit] {
        #expect(AIProviderRouting.fallback(for: connection, primary: "main", error: error, hasVisibleOutput: false) == nil)
    }
}

@MainActor private final class ConcurrentRunner: OperationRunner {
    var stopped = false
    var sink: AsyncStream<OperationEvent>.Continuation?
    func start() {}
    func stop() { stopped = true; cancel() }
    func cancel() { sink?.yield(.cancelled); sink?.finish(); sink = nil }
    func run(_ request: OperationRequest) -> AsyncStream<OperationEvent> {
        AsyncStream { sink = $0; $0.yield(.started(generation: 1)) }
    }
}

@Test @MainActor func pinnedRequestsAreIndependentBoundedAndClearTogether() throws {
    var runners: [ConcurrentRunner] = []
    let settings = routedSettings()
    var notices: [String] = []
    let environment = OperationsEnvironment()
    let operations = SelectionOperationsController(environment: environment, settings: { settings }, aiConfigured: { true },
        notice: { notices.append($0) }, readable: { true }, makeRunner: {
            let runner = ConcurrentRunner(); runners.append(runner); return runner
        })
    defer { operations.stop() }
    operations.perform(providerRequest(settings), source: nil, toolbarRect: nil)
    let first = try #require(operations.window)
    first.setPinned()
    operations.perform(providerRequest(settings), source: nil, toolbarRect: nil)
    #expect(runners.count == 2 && !runners[0].stopped)
    first.state.cancel()
    #expect(!runners[1].stopped && operations.window?.state.isBusy == true)
    operations.window?.setPinned()
    operations.perform(providerRequest(settings), source: nil, toolbarRect: nil)
    operations.window?.setPinned()
    operations.perform(providerRequest(settings), source: nil, toolbarRect: nil)
    operations.window?.setPinned()
    operations.perform(providerRequest(settings), source: nil, toolbarRect: nil)
    #expect(runners.count == 4 && operations.windows.count == 4)
    #expect(notices.last?.contains("4") == true)
    operations.clearCurrentContent()
    #expect(operations.windows.isEmpty && runners.allSatisfy(\.stopped))
}
