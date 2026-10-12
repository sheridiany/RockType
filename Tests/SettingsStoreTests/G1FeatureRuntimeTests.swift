import AppKit
import Observation
import Testing
import RoarkTCore
import RoarkTPlatform
@testable import RoarkTApp

@MainActor @Observable private final class FeaturePreferences { var settings = AppSettings.defaults }
@MainActor private final class FeatureRegistrar: HotkeyRegistering {
    var entries: [(Shortcut, @MainActor () -> Void)] = []
    func register(_ shortcut: Shortcut, handler: @escaping @MainActor () -> Void) throws { entries.append((shortcut, handler)) }
    func stop() { entries.removeAll() }
}

@MainActor private final class FeatureRunner: OperationRunner {
    var requests = 0
    var stops = 0
    func start() {}
    func stop() { stops += 1 }
    func cancel() {}
    func run(_ request: OperationRequest) -> AsyncStream<OperationEvent> { requests += 1; return AsyncStream { _ in } }
}

@Suite(.serialized) @MainActor struct G1FeatureRuntimeTests {
    @Test func legacyAndPartialFeatureSettingsRemainEnabled() throws {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings.defaults)) as? [String: Any])
        json.removeValue(forKey: "features")
        let old = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(FeatureSettings.Feature.allCases.allSatisfy { old.enabledFeatures[$0] })
        json["features"] = ["voice": false]
        let partial = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(!partial.enabledFeatures.voice)
        #expect(FeatureSettings.Feature.allCases.filter { $0 != .voice }.allSatisfy { partial.enabledFeatures[$0] })
        #expect(partial.input == old.input)
    }
    @Test func switchesUnregisterWithoutConflictsAndRejectAlreadyQueuedHandlers() async throws {
        let prefs = FeaturePreferences(), registrar = FeatureRegistrar()
        let textKey = Shortcut(key: "k", modifiers: [.command, .option]), imageKey = Shortcut(key: "i", modifiers: [.command, .option])
        prefs.settings.templates[2].shortcut = textKey
        var imageTemplate = OperationTemplate(id: "synthetic-image", name: "Synthetic", icon: "photo", prompt: "Synthetic", input: .image)
        imageTemplate.shortcut = imageKey; prefs.settings.templates.append(imageTemplate)
        var fired = 0, voice: [Bool] = []
        let center = HotkeyCenter(read: { prefs.settings.shortcuts }, write: { prefs.settings.shortcuts = $0 }, showSettings: {},
            readTemplates: { prefs.settings.templates }, readFeatures: { prefs.settings.enabledFeatures }, selection: { _ in fired += 1 },
            registrar: registrar, allowed: { true }, trusted: { true }, voiceListening: { voice.append($0); return true })
        center.templateAction = { _ in fired += 1 }; center.start(); defer { center.stop() }
        #expect(voice == [true])
        let stale = try #require(registrar.entries.first { $0.0 == textKey }?.1)
        prefs.settings.enabledFeatures.selectionShortcuts = false
        stale(); #expect(fired == 0)
        for _ in 0..<1000 where center.statuses[.translateSelection] != .disabled { await Task.yield() }
        #expect(center.statuses[.translateSelection] == .disabled && center.statuses[.summarizeSelection] == .disabled)
        #expect(center.templateStatuses["polish"] == .disabled && !registrar.entries.contains { $0.0 == textKey })
        // Disabled text definitions may share an enabled image key without reporting a conflict.
        prefs.settings.templates[2].shortcut = imageKey
        center.retry()
        #expect(center.templateStatuses["synthetic-image"] == .registered)
        prefs.settings.enabledFeatures.screenshot = false; center.retry()
        #expect(center.statuses[.screenshot] == .disabled && center.statuses[.screenshotHistory] == .disabled)
        #expect(center.templateStatuses["synthetic-image"] == .disabled && !registrar.entries.contains { $0.0 == imageKey })
        prefs.settings.enabledFeatures.screenshot = true; prefs.settings.enabledFeatures.screenshotHistory = false; center.retry()
        #expect(center.statuses[.screenshot] == .registered && center.statuses[.screenshotHistory] == .disabled)
        prefs.settings.enabledFeatures.pinning = false; center.retry()
        for action in [HotkeyCenter.Action.togglePins, .closePins, .nextPin] { #expect(center.statuses[action] == .disabled) }
        prefs.settings.enabledFeatures.voice = false; center.retry()
        #expect(center.statuses[.voiceHoldToTalk] == .disabled && voice == [true, false])
        prefs.settings.templates[2].shortcut = textKey
        prefs.settings.enabledFeatures = FeatureSettings(); center.retry()
        #expect(center.templateStatuses["polish"] == .registered && center.templateStatuses["synthetic-image"] == .registered)
        #expect(center.statuses[.screenshotHistory] == .registered && voice == [true, false, true])
        stale(); #expect(fired == 0)
        center.beginRecording(.translateSelection)
        prefs.settings.enabledFeatures.selectionShortcuts = false
        for _ in 0..<1000 where center.statuses[.translateSelection] != .disabled { await Task.yield() }
        #expect(center.statuses[.translateSelection] == .disabled && center.templateStatuses["polish"] == .disabled && registrar.entries.isEmpty)
        center.cancelRecording()
    }
    @Test func disablingTheLastEntryStopsItsResultsButKeepsOtherFeatures() {
        var settings = AppSettings.defaults
        let runner = FeatureRunner(), environment = OperationsEnvironment()
        let operations = SelectionOperationsController(environment: environment, settings: { settings }, aiConfigured: { true }, notice: { _ in }, readable: { true }, makeRunner: { runner })
        defer { operations.stop() }
        func request(_ method: ContentSnapshot.CaptureMethod) -> OperationRequest {
            .init(session: .init(snapshot: .init(text: "A synthetic source for testing", source: .init(pid: 0, applicationName: "Synthetic"), method: method)), template: .defaults[2], settings: settings)
        }
        operations.perform(request(.accessibility), source: nil, toolbarRect: nil)
        settings.enabledFeatures.selectionToolbar = false; operations.settingsChanged()
        #expect(operations.window?.isVisible == true)
        settings.enabledFeatures.selectionShortcuts = false; operations.settingsChanged()
        #expect(operations.window == nil && runner.stops > 0)
        operations.perform(request(.accessibility), source: nil, toolbarRect: nil)
        #expect(runner.requests == 1)
        operations.perform(request(.screenshotOCR), source: nil, toolbarRect: nil)
        #expect(runner.requests == 2 && operations.window?.isVisible == true)
        settings.enabledFeatures.screenshot = false; operations.settingsChanged()
        #expect(operations.window == nil)
        settings.enabledFeatures.selectionToolbar = true; operations.settingsChanged()
        operations.perform(request(.accessibility), source: nil, toolbarRect: nil)
        #expect(runner.requests == 3)
    }
    @Test func toolbarAndExplicitCaptureHaveIndependentLifetimes() async {
        var settings = AppSettings.defaults, reads = 0, performed = 0
        let source = ContentSnapshot.Source(pid: 42, bundleID: "synthetic.editor", applicationName: "Synthetic")
        let capture = SelectionCapture(allowed: { true }, context: { .init(source: source, isCurrent: { true }) }, read: {
            reads += 1; return .init(status: .success, text: "Synthetic", rect: nil)
        }, copy: { Issue.record("Unexpected clipboard fallback"); return nil })
        let controller = SelectionController(settings: { settings }, perform: { _, _, _ in performed += 1 }, search: { _, _ in }, notice: { _ in },
            allowed: { true }, capture: capture, frontmost: { source })
        controller.start(); defer { controller.stop() }
        #expect(controller.listeningForSelection)
        settings.enabledFeatures.selectionToolbar = false; controller.settingsChanged()
        #expect(!controller.listeningForSelection)
        controller.trigger(.translateSelection)
        for _ in 0..<1000 where performed == 0 { await Task.yield() }
        #expect(reads == 1 && performed == 1)
        settings.enabledFeatures.selectionShortcuts = false; controller.settingsChanged()
        controller.trigger(.translateSelection); controller.triggerTemplate("polish")
        for _ in 0..<20 { await Task.yield() }
        #expect(reads == 1 && performed == 1)
        settings.enabledFeatures.selectionToolbar = true; controller.settingsChanged()
        #expect(controller.listeningForSelection)
        controller.performAction("translate", captured: .init(snapshot: .init(text: "Synthetic", source: source, method: .accessibility), isCurrent: { true }), fromToolbar: true)
        #expect(performed == 2)
    }
}
