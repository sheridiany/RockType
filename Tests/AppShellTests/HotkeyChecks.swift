import Observation
import RoarkTCore
import RoarkTPlatform

@MainActor @Observable final class Preferences {
    var settings = ShortcutSettings()
    var allowed = true
    var voiceEnabled = false
    var trusted = true
    var settingsOpened = 0
    var actions: [HotkeyCenter.Action] = []
    var selections: [ShortcutAction] = []
}
@MainActor final class Registrar: HotkeyRegistering {
    var registered: [Shortcut] = []
    var handlers: [@MainActor () -> Void] = []
    var conflict: Shortcut?
    var stops = 0
    func register(_ shortcut: Shortcut, handler: @escaping @MainActor () -> Void) throws {
        if shortcut == conflict { throw GlobalHotkeys.Failure.conflict }
        registered.append(shortcut); handlers.append(handler)
    }
    func stop() { registered = []; handlers = []; stops += 1 }
}

@main struct HotkeyChecks {
    @MainActor static func main() async {
        let prefs = Preferences(), registrar = Registrar()
        let center = HotkeyCenter(read: { prefs.settings }, write: { prefs.settings = $0 },
                                  showSettings: { prefs.settingsOpened += 1 },
                                  comingSoon: { prefs.actions.append($0) }, selection: { prefs.selections.append($0) }, registrar: registrar,
                                  allowed: { prefs.allowed }, trusted: { prefs.trusted },
                                  voiceListening: { prefs.voiceEnabled = $0; return true })
        var screenshots = 0
        center.screenshotAction = { screenshots += 1 }
        center.start()
        precondition(registrar.registered.count == 3 && prefs.voiceEnabled)
        registrar.handlers.forEach { $0() }
        // M4 screenshot runs the real capture; M3-6 forwards selection actions. Nothing is "coming soon".
        precondition(screenshots == 1 && prefs.actions.isEmpty && prefs.selections == [.translateSelection, .summarizeSelection])
        prefs.allowed = false
        registrar.handlers.forEach { $0() }
        precondition(screenshots == 1 && prefs.actions.isEmpty && prefs.selections.count == 2, "Secure Input must suppress every action")
        prefs.allowed = true
        let staleAction = registrar.handlers.first
        let replacement = Shortcut(key: "k", modifiers: [.command, .option])
        center.set(replacement, for: .screenshot)
        precondition(prefs.settings.bindings[.screenshot] == replacement)
        precondition(registrar.registered.contains(replacement))
        staleAction?(); precondition(screenshots == 1 && prefs.selections.count == 2, "Stale handler must not run after re-registration")
        // A caller other than this view changes the observable Store.
        prefs.settings.bindings[.screenshot] = Shortcut(key: "j", modifiers: .control)
        for _ in 0..<10 { await Task.yield() }
        precondition(registrar.registered.contains(Shortcut(key: "j", modifiers: .control)))
        center.set(Shortcut(key: "T", modifiers: [.control, .option]), for: .screenshot)
        precondition(center.statuses[.screenshot] == .conflict && center.statuses[.translateSelection] == .conflict)
        precondition(registrar.registered.count == 1)
        center.restoreDefault(for: .screenshot)
        precondition(center.statuses[.screenshot] == .registered && center.statuses[.translateSelection] == .registered)
        registrar.conflict = Shortcut.defaults[.screenshot]; center.retry()
        precondition(center.statuses[.screenshot] == .conflict)
        registrar.conflict = nil; center.retry()
        precondition(center.statuses[.screenshot] == .registered)
        prefs.trusted = false; center.refreshPermissions()
        precondition(center.statuses[.voiceHoldToTalk] == .needsAccessibility)
        prefs.trusted = true; center.refreshPermissions()
        precondition(center.statuses[.voiceHoldToTalk] == .registered)
        center.beginRecording(.screenshot)
        precondition(registrar.registered.isEmpty && !prefs.voiceEnabled)
        prefs.settings.showSettings = Shortcut(key: ",", modifiers: [.command, .option])
        for _ in 0..<10 { await Task.yield() }
        precondition(registrar.registered.isEmpty, "Settings observation must not end recording")
        center.cancelRecording()
        precondition(registrar.registered.count == 4)
        registrar.handlers.last?(); precondition(prefs.settingsOpened == 1)
        center.set(Shortcut(key: "a", modifiers: .shift), for: .screenshot)
        precondition(center.statuses[.screenshot] == .unsupported)
        center.set(nil, for: .screenshot)
        precondition(center.statuses[.screenshot] == .unassigned)
        center.stop()
        precondition(!prefs.voiceEnabled && registrar.registered.isEmpty)
        prefs.settings.bindings[.screenshot] = replacement
        for _ in 0..<10 { await Task.yield() }
        precondition(registrar.registered.isEmpty)
        print("Hotkey center checks passed")
    }
}
