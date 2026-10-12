import AppKit
import SwiftUI
import Testing
import RoarkTCore
import RoarkTPlatform
@testable import RoarkTApp

@Suite(.serialized) @MainActor struct G3SettingsTests {
    @Test func overviewBindingsPersistAndPreserveIndependentPreferences() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = SettingsPersistence(fileURL: directory.appendingPathComponent("settings.json"))
        let store = SettingsStore(persistence: persistence)
        store.settings.input.scheme = .flypy
        store.settings.screenshot.historyDiskDays = 19
        store.settings.voice.cleanUpLocally = false
        let binding = Binding(get: { store.settings }, set: { store.settings = $0 })
        #expect(store.settings.features == nil)
        for item in SettingsFeature.allCases { item.binding(in: binding).wrappedValue = false }
        SettingsFeature.voice.binding(in: binding).wrappedValue = true
        #expect(store.settings.enabledFeatures.voice)
        #expect(!store.settings.enabledFeatures.screenshot)
        #expect(!store.settings.input.candidateTranslation)
        // Restoring candidate translation must not re-enable the seven feature switches.
        SettingsFeature.candidateTranslation.binding(in: binding).wrappedValue = true
        store.flush()
        let loaded = try persistence.load().settings
        #expect(loaded == store.settings)
        #expect(loaded.input.scheme == .flypy)
        #expect(loaded.screenshot.historyDiskDays == 19)
        #expect(!loaded.voice.cleanUpLocally)
        #expect(loaded.enabledFeatures.voice && loaded.input.candidateTranslation)
        #expect(FeatureSettings.Feature.allCases.filter { $0 != .voice }.allSatisfy { !loaded.enabledFeatures[$0] })
    }

    @Test func statusUsesCurrentShortcutPermissionsAndAIOptIn() {
        var settings = AppSettings.defaults
        let granted = Set(Permissions.Kind.allCases)
        settings.shortcuts.bindings[.screenshot] = Shortcut(key: "2", modifiers: [.control, .shift])
        #expect(SettingsFeature.screenshot.status(settings: settings, granted: granted, aiConfigured: false).text.contains("⌃⇧2"))
        #expect(SettingsFeature.voice.status(settings: settings, granted: [], aiConfigured: false).text == "需要麦克风权限")
        settings.enabledFeatures.voice = false
        #expect(!SettingsFeature.voice.status(settings: settings, granted: [], aiConfigured: false).attention)
        #expect(SettingsFeature.inputMethodAI.status(settings: settings, granted: granted, aiConfigured: true).text.contains("启用 AI 动作"))
        settings.input.inputAI = InputAISettings(); settings.input.inputAI?.enabled = true
        #expect(SettingsFeature.inputMethodAI.status(settings: settings, granted: granted, aiConfigured: true).text.contains("⌥Tab"))
        #expect(SettingsNavigation().section == .features)
    }

    @Test func disabledFeatureActuallyDisablesItsSwiftUIContent() {
        _ = NSApplication.shared
        var disabled = AppSettings.defaults
        disabled.enabledFeatures.voice = false
        var observed: [Bool] = []
        let host = NSHostingView(rootView: SettingsFeatureContent(item: .voice, settings: .constant(disabled)) {
            G3EnabledProbe { observed.append($0) }
        })
        host.frame = CGRect(x: 0, y: 0, width: 500, height: 160)
        host.layoutSubtreeIfNeeded()
        #expect(observed.last == false)
        host.rootView = SettingsFeatureContent(item: .voice, settings: .constant(.defaults)) {
            G3EnabledProbe { observed.append($0) }
        }
        host.layoutSubtreeIfNeeded()
        #expect(observed.last == true)
    }

    @Test func renderEnabledDisabledAndProviderStates() throws {
        guard let path = ProcessInfo.processInfo.environment["ROARKT_G3_RENDER_DIR"] else { return }
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let permissions = PermissionCenter(read: { _ in .granted }, request: { _ in Issue.record("Render requested permission") }, open: { _ in Issue.record("Render opened System Settings"); return false })
        let hotkeys = HotkeyCenter(read: { .init() }, write: { _ in }, showSettings: {}, allowed: { false }, trusted: { false })
        let connection = ShellConnectionModel()
        connection.keyExists = { _ in true }; connection.readKey = { _ in nil }
        connection.runTests = { _, _ in Issue.record("Render attempted network test"); return [] }
        var enabled = AppSettings.defaults
        enabled.ai.id = "g3-render-default"; enabled.ai.name = "兼容服务"; enabled.ai.baseURL = "https://example.invalid/v1"; enabled.ai.defaultModel = "text-model"
        enabled.input.inputAI = InputAISettings(); enabled.input.inputAI?.enabled = true
        var secondary = enabled.ai; secondary.id = "g3-render-local"; secondary.name = "本机服务"; secondary.baseURL = "http://127.0.0.1:3425/v1"
        enabled.aiProviders = [secondary]
        var disabled = enabled
        for feature in FeatureSettings.Feature.allCases { disabled.enabledFeatures[feature] = false }
        disabled.input.candidateTranslation = false
        let scenarios: [(String, SettingsSection, AppSettings)] = [
            ("features-enabled", .features, enabled), ("features-disabled", .features, disabled),
            ("voice-disabled", .voice, disabled), ("input-disabled", .input, disabled),
            ("selection-disabled", .selection, disabled), ("screenshot-disabled", .screenshot, disabled),
            ("shortcuts-disabled", .shortcuts, disabled), ("providers", .ai, enabled)]
        for (name, section, settings) in scenarios {
            for dark in [false, true] {
                connection.refresh(settings.ai)
                let size = CGSize(width: 900, height: 800)
                let view = ShellSettingsView(settings: .constant(settings), login: LoginItemController(), connection: connection,
                    sections: ShellSettingsSections(permissions: permissions, hotkeys: hotkeys), persistenceMessage: "修改自动保存", exportDiagnostics: {}, section: .constant(section))
                    .environment(\.colorScheme, dark ? .dark : .light).frame(width: size.width, height: size.height)
                let host = NSHostingView(rootView: view)
                let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false; panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua); panel.contentView = host
                host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(name + (dark ? "-dark.png" : "-light.png")))
                panel.contentView = nil; panel.close()
            }
        }
        connection.cancel()
    }
}

private struct G3EnabledProbe: NSViewRepresentable {
    var report: (Bool) -> Void
    @Environment(\.isEnabled) private var enabled
    func makeNSView(context: Context) -> NSView { report(enabled); return NSView() }
    func updateNSView(_ nsView: NSView, context: Context) { report(enabled) }
}
