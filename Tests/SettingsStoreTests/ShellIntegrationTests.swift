import Foundation
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor private final class ShellRegistrar: HotkeyRegistering {
    var entries: [(Shortcut, @MainActor () -> Void)] = []
    func handler(_ shortcut: Shortcut) -> (@MainActor () -> Void)? { entries.first { $0.0 == shortcut }?.1 }
    func register(_ shortcut: Shortcut, handler: @escaping @MainActor () -> Void) throws { entries.append((shortcut, handler)) }
    func startFn(handler: @escaping @MainActor () -> Void) throws {}
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
                              showSettings: {}, comingSoon: { received.append($0) },
                              registrar: registrar, allowed: { true }, trusted: { true })
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
    for completed in [true, false] {
        #expect(OnboardingWindowController.launchAction(arguments: ["--gallery", "--show-settings"], completed: completed) == .none)
        #expect(OnboardingWindowController.launchAction(arguments: ["--render-gallery", "/tmp/gallery", "--show-settings"], completed: completed) == .none)
    }
}
