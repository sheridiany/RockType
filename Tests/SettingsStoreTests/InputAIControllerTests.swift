import Foundation
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor private final class ConfigurationSink: InputAIConfiguring {
    var onDisconnect: (() -> Void)?
    var payloads: [[String: String]] = []
    var held: CheckedContinuation<Void, Error>?
    var holdNext = false
    var invalidations = 0
    var clears = 0
    func configure(_ config: [String: String]) async throws {
        payloads.append(config)
        if holdNext {
            holdNext = false
            try await withCheckedThrowingContinuation { held = $0 }
        }
    }
    func release() { held?.resume(); held = nil }
    func invalidate() { invalidations += 1; held?.resume(throwing: CancellationError()); held = nil }
    func clearAndInvalidate() { clears += 1; payloads.append([:]); invalidate() }
}

@MainActor private func awaitInputAI(_ predicate: () -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(4)
    while !predicate(), ContinuousClock.now < deadline { await Task.yield() }
    #expect(predicate())
}
@MainActor private func configuredStore(_ url: URL) -> SettingsStore {
    let store = SettingsStore(persistence: SettingsPersistence(fileURL: url))
    store.settings.ai.baseURL = "https://example.invalid/v1"
    store.settings.ai.defaultModel = "synthetic-model"
    var inputAI = InputAISettings(); inputAI.enabled = true
    store.settings.input.inputAI = inputAI
    return store
}

@Test @MainActor func inputAIStartupSettingsTemplatesAndKeyEventsSynchronizeWithoutPersistingSecrets() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("settings.json")
    let store = configuredStore(url), sink = ConfigurationSink()
    var key: String? = "synthetic-first-key"
    var starts = 0, stops = 0
    let controller = InputAIController(store: store, transport: sink, secret: { _ in key },
        beginKeyMonitoring: { starts += 1; return true }, endKeyMonitoring: { stops += 1 })
    controller.start(); controller.start()
    await awaitInputAI { sink.payloads.count == 1 }
    #expect(starts == 1)
    #expect(sink.payloads.last?["apiKey"] == key)
    #expect(sink.payloads.last?["model"] == "synthetic-model")
    #expect(sink.payloads.last?["timeout"] == "30.0")
    #expect(sink.payloads.last?["translatePrompt"]?.contains("代码块、行内代码、命令、URL") == true)
    #expect(sink.payloads.last?["polishPrompt"]?.contains("不增加事实") == true)
    store.settings.ai.defaultModel = "synthetic-replacement"
    await awaitInputAI { sink.payloads.last?["model"] == "synthetic-replacement" }
    let polish = try #require(store.settings.templates.firstIndex { $0.id == "polish" })
    store.settings.templates[polish].prompt = "Synthetic edited polish"
    await awaitInputAI { sink.payloads.last?["polishPrompt"] == "Synthetic edited polish" }
    #expect(sink.payloads.last?["rewritePrompt"]?.hasPrefix("Synthetic edited polish") == true)
    let translate = try #require(store.settings.templates.firstIndex { $0.id == "translate" })
    store.settings.templates[translate].prompt = "Synthetic edited translation {{target}}"
    await awaitInputAI { sink.payloads.last?["translatePrompt"] == "Synthetic edited translation {{target}}" }
    key = "synthetic-second-key"
    NotificationCenter.default.post(name: InputAIKeychainMonitor.changed, object: nil)
    await awaitInputAI { sink.payloads.last?["apiKey"] == key }
    key = nil
    NotificationCenter.default.post(name: InputAIKeychainMonitor.changed, object: nil)
    await awaitInputAI { sink.payloads.last == [:] }
    store.flush()
    let persisted = try String(contentsOf: url, encoding: .utf8)
    #expect(!persisted.contains("synthetic-first-key") && !persisted.contains("synthetic-second-key") && !persisted.contains("apiKey"))
    controller.stop(); controller.stop()
    #expect(sink.clears == 1 && stops == 1)
}

@Test @MainActor func inputAIChangesDuringOutstandingConfigurationAreSerializedAndDisableRevokes() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = configuredStore(directory.appendingPathComponent("settings.json")), sink = ConfigurationSink()
    let controller = InputAIController(store: store, transport: sink, secret: { _ in "synthetic-key" },
        beginKeyMonitoring: { true }, endKeyMonitoring: {})
    sink.holdNext = true; controller.start()
    await awaitInputAI { sink.held != nil }
    store.settings.ai.defaultModel = "synthetic-second"
    store.settings.input.inputAI?.enabled = false
    #expect(sink.payloads.count == 1)
    sink.release()
    await awaitInputAI { sink.payloads.count == 2 }
    #expect(sink.payloads.last == [:])
    store.settings.input.inputAI?.enabled = true
    await awaitInputAI { sink.payloads.last?["model"] == "synthetic-second" }
    controller.stop(); store.flush()
}

@Test @MainActor func inputAIStopDiscardsInFlightSyncAndRestartReadsFreshConfiguration() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = configuredStore(directory.appendingPathComponent("settings.json")), sink = ConfigurationSink()
    let controller = InputAIController(store: store, transport: sink, secret: { _ in "synthetic-key" },
        beginKeyMonitoring: { true }, endKeyMonitoring: {})
    sink.holdNext = true; controller.start()
    await awaitInputAI { sink.held != nil }
    controller.stop()
    store.settings.ai.defaultModel = "synthetic-after-stop"
    controller.start()
    await awaitInputAI { sink.payloads.last?["model"] == "synthetic-after-stop" }
    #expect(sink.clears == 1)
    controller.stop(); store.flush()
}

@Test @MainActor func inputAIReconnectAndKeyReadFailureNeverReuseStaleCredentials() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = configuredStore(directory.appendingPathComponent("settings.json")), sink = ConfigurationSink()
    var denied = false
    let controller = InputAIController(store: store, transport: sink, secret: { _ in
        if denied { throw CocoaError(.fileReadNoPermission) }; return "synthetic-key"
    }, beginKeyMonitoring: { true }, endKeyMonitoring: {})
    controller.start()
    await awaitInputAI { sink.payloads.count == 1 }
    sink.onDisconnect?()
    await awaitInputAI { sink.payloads.count == 2 }
    denied = true; controller.refresh()
    await awaitInputAI { sink.payloads.last == [:] }
    controller.stop(); store.flush()
}

@Test @MainActor func inputAIInvalidConfigurationClearsAndUnrelatedEditsDoNotResend() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = configuredStore(directory.appendingPathComponent("settings.json")), sink = ConfigurationSink()
    let controller = InputAIController(store: store, transport: sink, secret: { _ in "synthetic-key" },
        beginKeyMonitoring: { true }, endKeyMonitoring: {})
    controller.start(); await awaitInputAI { sink.payloads.count == 1 }
    store.settings.general.showBeijingTime = true
    for _ in 0..<50 { await Task.yield() }
    #expect(sink.payloads.count == 1)
    store.settings.ai.baseURL = "http://example.invalid"
    await awaitInputAI { sink.payloads.last == [:] }
    controller.stop(); store.flush()
}

@Test @MainActor func inputAIShortcutConflictChecksGlobalBindingsWithoutRegisteringIMEKey() {
    #expect(!InputAISettingsSection.conflicts(Shortcut(key: "tab", modifiers: .option), settings: .init()))
    #expect(InputAISettingsSection.conflicts(Shortcut(key: "T", modifiers: [.control, .option]), settings: .init()))
    var settings = ShortcutSettings(); settings.showSettings = Shortcut(key: "tab", modifiers: .option)
    #expect(InputAISettingsSection.conflicts(Shortcut(key: "tab", modifiers: .option), settings: settings))
}

@Test @MainActor func inputAIAppAcceptsOnlySharedEndpointPolicyAndReplaysAckAcrossDisconnect() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = configuredStore(directory.appendingPathComponent("settings.json")), sink = ConfigurationSink()
    store.settings.ai.baseURL = "http://127.0.0.1:8080/v1"
    let controller = InputAIController(store: store, transport: sink, secret: { _ in "synthetic-key" },
        beginKeyMonitoring: { true }, endKeyMonitoring: {})
    sink.holdNext = true; controller.start()
    await awaitInputAI { sink.held != nil }
    #expect(sink.payloads.last?["baseURL"] == "http://127.0.0.1:8080/v1")
    sink.release(); sink.onDisconnect?()
    await awaitInputAI { sink.payloads.count == 2 }
    for baseURL in ["http://[::1]:8080/v1", "http://localhost/v1"] {
        store.settings.ai.baseURL = baseURL
        await awaitInputAI { sink.payloads.last?["baseURL"] == baseURL }
    }
    store.settings.ai.baseURL = "http://localhost.example.invalid"
    await awaitInputAI { sink.payloads.last == [:] }
    controller.stop(); store.flush()
}

@Test @MainActor func inputAIUsesTaskProviderAndItsOwnKeyAndFallback() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = configuredStore(directory.appendingPathComponent("settings.json")), sink = ConfigurationSink()
    var provider = AIConnectionSettings()
    provider.id = "input-provider"; provider.baseURL = "https://input.invalid/v1"; provider.defaultModel = "input-default"
    provider.fallbackModel = "input-backup"
    store.settings.aiProviders = [provider]
    store.settings.aiTaskRoutes = [AITask.inputAI.rawValue: .init(providerID: provider.id, model: "input-task-model")]
    var accounts: [String] = []
    let controller = InputAIController(store: store, transport: sink, secret: { accounts.append($0); return "synthetic-input-key" },
        beginKeyMonitoring: { true }, endKeyMonitoring: {})
    controller.start()
    await awaitInputAI { !sink.payloads.isEmpty }
    #expect(accounts == ["input-provider"])
    #expect(sink.payloads.last?["baseURL"] == provider.baseURL)
    #expect(sink.payloads.last?["model"] == "input-task-model")
    #expect(sink.payloads.last?["fallbackModel"] == "input-backup")
    store.settings.aiProviders = []
    await awaitInputAI { sink.payloads.last == [:] }
    controller.stop(); store.flush()
}

@Test @MainActor func g1InputAIMasterSwitchRevokesConfigurationWithoutReadingSecret() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = configuredStore(directory.appendingPathComponent("settings.json")), sink = ConfigurationSink()
    store.settings.enabledFeatures.inputMethodAI = false
    var reads = 0
    let controller = InputAIController(store: store, transport: sink, secret: { _ in reads += 1; return "synthetic" }, beginKeyMonitoring: { true }, endKeyMonitoring: {})
    controller.start(); defer { controller.stop() }
    await awaitInputAI { sink.payloads.count == 1 }
    #expect(sink.payloads.last == [:] && reads == 0)
    store.settings.enabledFeatures.inputMethodAI = true
    await awaitInputAI { sink.payloads.last?["apiKey"] == "synthetic" }
    let before = reads
    store.settings.enabledFeatures.inputMethodAI = false
    await awaitInputAI { sink.payloads.last == [:] }
    #expect(reads == before)
}
