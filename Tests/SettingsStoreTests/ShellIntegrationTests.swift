import Foundation
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor private final class ShellRegistrar: HotkeyRegistering {
    var entries: [(Shortcut, @MainActor () -> Void)] = []
    func handler(_ shortcut: Shortcut) -> (@MainActor () -> Void)? { entries.first { $0.0 == shortcut }?.1 }
    func register(_ shortcut: Shortcut, handler: @escaping @MainActor () -> Void) throws { entries.append((shortcut, handler)) }
    func stop() { entries.removeAll() }
}

@MainActor @Test func shellShortcutsFollowPersistedStoreAndStop() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = SettingsPersistence(fileURL: directory.appendingPathComponent("settings.json"))
    let store = SettingsStore(persistence: persistence)
    let registrar = ShellRegistrar()
    var received: [HotkeyCenter.Action] = []
    let center = HotkeyCenter(read: { store.settings.shortcuts }, write: { store.settings.shortcuts = $0 },
                              showSettings: {}, unavailableAction: { received.append($0) },
                              registrar: registrar, allowed: { true }, trusted: { true })
    center.screenshotAction = { received.append(.screenshot) }
    center.start()
    defer { center.stop() }
    let original = try #require(Shortcut.defaults[.screenshot])
    let stale = try #require(registrar.handler(original))
    stale()
    #expect(received == [.screenshot])
    let replacement = Shortcut(key: "k", modifiers: [.control, .option])
    store.settings.shortcuts.bindings[.screenshot] = replacement
    // Observation delivers on the main actor after SettingsStore's didSet.
    for _ in 0..<100 where registrar.handler(replacement) == nil { await Task.yield() }
    #expect(registrar.handler(original) == nil)
    let current = try #require(registrar.handler(replacement))
    stale()
    #expect(received.count == 1)
    current()
    #expect(received == [.screenshot, .screenshot])
    center.set(Shortcut.defaults[.translateSelection], for: .screenshot)
    #expect(center.statuses[.screenshot] == .conflict)
    #expect(center.statuses[.translateSelection] == .conflict)
    center.restoreDefault(for: .screenshot)
    store.flush()
    #expect(SettingsStore(persistence: persistence).settings.shortcuts == center.settings)
    center.stop()
    current()
    #expect(registrar.entries.isEmpty)
    #expect(received.count == 2)
}

@MainActor @Test func galleryWinsOverSettingsAndFirstLaunch() {
    #expect(SettingsLaunchPolicy.action(arguments: ["--gallery", "--show-settings"]) == .none)
    #expect(SettingsLaunchPolicy.action(arguments: ["--render-gallery", "/tmp/gallery", "--show-settings"]) == .none)
}

@MainActor @Test func selectionHotkeysForwardAndRejectStaleOrProtectedEvents() throws {
    let registrar = ShellRegistrar()
    var settings = ShortcutSettings()
    var allowed = true
    var received: [ShortcutAction] = []
    var placeholders: [HotkeyCenter.Action] = []
    let center = HotkeyCenter(read: { settings }, write: { settings = $0 }, showSettings: {},
        unavailableAction: { placeholders.append($0) }, selection: { received.append($0) },
        registrar: registrar, allowed: { allowed }, trusted: { true })
    center.start()
    defer { center.stop() }
    let translateShortcut = try #require(Shortcut.defaults[.translateSelection])
    let translate = try #require(registrar.handler(translateShortcut))
    let summarizeShortcut = try #require(Shortcut.defaults[.summarizeSelection])
    let summarize = try #require(registrar.handler(summarizeShortcut))
    translate(); summarize()
    #expect(received == [.translateSelection, .summarizeSelection])
    #expect(center.notice == nil && placeholders.isEmpty)
    allowed = false; translate(); summarize()
    #expect(received.count == 2)
    allowed = true
    center.beginRecording(.translateSelection); translate()
    #expect(received.count == 2)
    center.cancelRecording()
    let replacement = Shortcut(key: "u", modifiers: [.control, .option])
    center.set(replacement, for: .translateSelection)
    translate()
    #expect(received.count == 2)
    let replacedHandler = try #require(registrar.handler(replacement))
    replacedHandler()
    #expect(received.last == .translateSelection && received.count == 3)
    let screenshot = try #require(Shortcut.defaults[.screenshot])
    let screenshotHandler = try #require(registrar.handler(screenshot))
    var screenshots = 0
    center.screenshotAction = { screenshots += 1 }
    screenshotHandler()
    // M4: screenshot starts the real capture instead of a placeholder notice.
    #expect(screenshots == 1 && placeholders.isEmpty)
    center.stop(); summarize()
    #expect(received.count == 3)
}

@MainActor @Test func voiceListenerOwnershipFollowsRecordingPermissionsAndConflicts() {
    let registrar = ShellRegistrar()
    var settings = ShortcutSettings()
    var trusted = true
    var monitorAvailable = true
    var transitions: [Bool] = []
    let center = HotkeyCenter(read: { settings }, write: { settings = $0 }, showSettings: {},
        registrar: registrar, allowed: { true }, trusted: { trusted }, voiceListening: {
            transitions.append($0); return !$0 || monitorAvailable
        })
    center.start()
    #expect(transitions == [true])
    #expect(registrar.entries.count == 7) // Fn is never registered by HotkeyCenter.
    center.beginRecording(.screenshot)
    #expect(transitions == [true, false] && center.statuses[.voiceHoldToTalk] == .recording)
    trusted = false; center.refreshPermissions()
    trusted = true; center.refreshPermissions()
    #expect(transitions == [true, false]) // Regrant cannot resume while recording.
    center.cancelRecording()
    #expect(transitions == [true, false, true])
    trusted = false; center.refreshPermissions()
    #expect(transitions.last == false && center.statuses[.voiceHoldToTalk] == .needsAccessibility)
    trusted = true; center.refreshPermissions()
    #expect(transitions.suffix(2) == [false, true])
    center.set(Shortcut(key: nil, modifiers: .function), for: .screenshot)
    #expect(center.statuses[.voiceHoldToTalk] == .conflict && transitions.last == false)
    center.restoreDefault(for: .screenshot)
    #expect(center.statuses[.voiceHoldToTalk] == .registered && transitions.last == true)
    center.set(nil, for: .voiceHoldToTalk)
    #expect(center.statuses[.voiceHoldToTalk] == .unassigned && transitions.last == false)
    monitorAvailable = false
    center.restoreDefault(for: .voiceHoldToTalk)
    #expect(center.statuses[.voiceHoldToTalk] == .unavailable)
    monitorAvailable = true; center.retry()
    #expect(center.statuses[.voiceHoldToTalk] == .registered)
    center.stop()
    #expect(transitions.last == false)
    let count = transitions.count
    trusted = false; center.refreshPermissions(); center.cancelRecording()
    #expect(transitions.count == count)
}

@MainActor @Test func screenshotGroupShortcutsDefaultsOverridesAndClearingSurviveReload() throws {
    var settings = ShortcutSettings()
    let actions: [HotkeyCenter.Action] = [.screenshotHistory, .togglePins, .closePins, .nextPin]
    // A settings document written before these actions contains none of the new keys.
    for action in actions { settings.bindings[action.core!] = nil }
    settings = try JSONDecoder().decode(ShortcutSettings.self, from: JSONEncoder().encode(settings))
    let registrar = ShellRegistrar()
    let center = HotkeyCenter(read: { settings }, write: { settings = $0 }, showSettings: {}, registrar: registrar, allowed: { true }, trusted: { true })
    center.start(); defer { center.stop() }
    var calls: [HotkeyCenter.Action] = []; center.screenshotGroupAction = { calls.append($0) }
    for action in actions {
        let shortcut = try #require(center.shortcut(for: action))
        let handler = try #require(registrar.handler(shortcut)); handler()
    }
    #expect(calls == actions)
    let defaults = Shortcut.defaults.values.map { "\($0.key ?? "nil"):\($0.modifiers.rawValue)" }
    #expect(Set(defaults).count == defaults.count)
    center.set(nil, for: .screenshotHistory)
    settings = try JSONDecoder().decode(ShortcutSettings.self, from: JSONEncoder().encode(settings))
    center.retry()
    #expect(center.shortcut(for: .screenshotHistory) == nil)
    #expect(center.statuses[.screenshotHistory] == .unassigned)
    #expect(center.statuses[.togglePins] == .registered)
    center.set(Shortcut.defaults[.screenshot], for: .nextPin)
    #expect(center.statuses[.nextPin] == .conflict && center.statuses[.screenshot] == .conflict)
    center.restoreDefault(for: .nextPin); center.restoreDefault(for: .screenshotHistory)
    #expect(center.statuses[.nextPin] == .registered && center.statuses[.screenshotHistory] == .registered)
}
