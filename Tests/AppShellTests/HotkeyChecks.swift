import Observation
import RoarkTCore
import RoarkTPlatform

@MainActor @Observable final class Preferences {
    var settings = ShortcutSettings()
    var allowed = true
    var probes = 0
    var settingsOpened = 0
    var actions: [HotkeyCenter.Action] = []
}
@MainActor final class Registrar: HotkeyRegistering {
    var registered: [Shortcut] = []
    var handlers: [@MainActor () -> Void] = []
    var fn: (@MainActor () -> Void)?
    var conflict: Shortcut?
    var fnDenied = false
    var stops = 0
    func register(_ shortcut: Shortcut, handler: @escaping @MainActor () -> Void) throws {
        if shortcut == conflict { throw GlobalHotkeys.Failure.conflict }
        registered.append(shortcut); handlers.append(handler)
    }
    func startFn(handler: @escaping @MainActor () -> Void) throws {
        if fnDenied { throw FnKeyMonitor.Failure.noPermission }
        fn = handler
    }
    func stop() { registered = []; handlers = []; fn = nil; stops += 1 }
}

@main struct HotkeyChecks {
    @MainActor static func main() async {
        let prefs = Preferences(), registrar = Registrar()
        let center = HotkeyCenter(read: { prefs.settings }, write: { prefs.settings = $0 },
                                  showSettings: { prefs.settingsOpened += 1 },
                                  comingSoon: { prefs.actions.append($0) }, registrar: registrar,
                                  allowed: { prefs.allowed }, trusted: { true }, probe: { prefs.probes += 1 })
        var screenshots = 0
        center.screenshotAction = { screenshots += 1 }
        center.start()
        precondition(registrar.registered.count == 3 && registrar.fn != nil)
        registrar.handlers.forEach { $0() }
        // M4: screenshot runs the real capture; selection actions are wired in M3-6.
        precondition(screenshots == 1)
        precondition(prefs.actions == [.translateSelection, .summarizeSelection])
        prefs.allowed = false
        registrar.handlers.forEach { $0() }
        precondition(prefs.actions.count == 2 && screenshots == 1, "Secure Input must suppress notices, diagnostics and capture")
        prefs.allowed = true
        let staleAction = registrar.handlers.first
        let staleFn = registrar.fn
        registrar.fn?(); precondition(prefs.probes == 1)
        prefs.allowed = false; registrar.fn?(); precondition(prefs.probes == 1)
        prefs.allowed = true
        let replacement = Shortcut(key: "k", modifiers: [.command, .option])
        center.set(replacement, for: .screenshot)
        precondition(prefs.settings.bindings[.screenshot] == replacement)
        precondition(registrar.registered.contains(replacement))
        staleAction?(); precondition(prefs.actions.count == 3)
        staleFn?(); precondition(prefs.probes == 1, "Queued old handler must not run after re-registration")
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
        registrar.fnDenied = true; center.retry()
        precondition(center.statuses[.voiceHoldToTalk] == .needsAccessibility)
        registrar.fnDenied = false; center.retry()
        precondition(center.statuses[.voiceHoldToTalk] == .registered)
        center.beginRecording(.screenshot)
        precondition(registrar.registered.isEmpty && registrar.fn == nil)
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
        let stoppedFn = registrar.fn
        center.stop(); stoppedFn?()
        precondition(prefs.probes == 1 && registrar.registered.isEmpty)
        prefs.settings.bindings[.screenshot] = replacement
        for _ in 0..<10 { await Task.yield() }
        precondition(registrar.registered.isEmpty)
        print("Hotkey center checks passed")
    }
}
