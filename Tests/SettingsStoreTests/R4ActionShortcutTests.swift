import Foundation
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor private final class ActionRegistrar: HotkeyRegistering {
    var entries: [(Shortcut, @MainActor () -> Void)] = []
    func register(_ shortcut: Shortcut, handler: @escaping @MainActor () -> Void) throws { entries.append((shortcut, handler)) }
    func stop() { entries.removeAll() }
}

@MainActor @Test func customActionShortcutsRejectConflictsProtectionAndStaleHandlers() throws {
    var settings = AppSettings.defaults
    let registrar = ActionRegistrar()
    var allowed = true, calls = 0
    let center = HotkeyCenter(read: { settings.shortcuts }, write: { settings.shortcuts = $0 }, showSettings: {},
        readTemplates: { settings.templates }, registrar: registrar, allowed: { allowed }, trusted: { true })
    center.templateAction = { _ in calls += 1 }
    center.start(); defer { center.stop() }
    #expect(registrar.entries.count == 3)
    let shortcut = Shortcut(key: "k", modifiers: [.option, .command])
    settings.templates[2].shortcut = shortcut; center.retry()
    #expect(center.templateStatuses["polish"] == .registered)
    let callback = try #require(registrar.entries.first { $0.0 == shortcut }?.1)
    callback(); #expect(calls == 1)
    allowed = false; callback(); #expect(calls == 1)
    allowed = true; center.beginTemplateRecording("polish"); callback()
    #expect(calls == 1 && registrar.entries.isEmpty)
    center.cancelRecording(); callback(); #expect(calls == 1)
    settings.templates[2].shortcut = Shortcut.defaults[.translateSelection]; center.retry()
    #expect(center.templateStatuses["polish"] == .conflict)
    #expect(center.statuses[.translateSelection] == .conflict)
    settings.templates[2].shortcut = shortcut; settings.templates[3].shortcut = shortcut; center.retry()
    #expect(center.templateStatuses["polish"] == .conflict && center.templateStatuses["explain"] == .conflict)
    settings.templates[2].shortcut = nil; settings.templates[3].shortcut = nil; center.retry()
    #expect(registrar.entries.count == 3)
}
