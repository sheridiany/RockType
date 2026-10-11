import AppKit
import SwiftUI
import RoarkTCore

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let store: SettingsStore
    private let login: LoginItemController
    private let connection: ShellConnectionModel
    private let sections: ShellSettingsSections
    var exportDiagnostics: () -> Void = {}

    init(store: SettingsStore, login: LoginItemController, connection: ShellConnectionModel,
         sections: ShellSettingsSections) {
        self.store = store
        self.login = login
        self.connection = connection
        self.sections = sections
    }

    func show() {
        login.refresh()
        if store.settings.general.launchAtLogin != login.enabled {
            store.settings.general.launchAtLogin = login.enabled
        }
        connection.refresh(store.settings.ai)
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Tokens.Size.settingsWidth, height: Tokens.Size.settingsHeight),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "RoarkT · 设置"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: Tokens.Size.settingsWidth, height: Tokens.Size.settingsHeight)
            window.contentView = NSHostingView(rootView: SettingsRoot(store: store, login: login, connection: connection,
                                                                     sections: sections, export: exportDiagnostics))
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingsRoot: View {
    @Bindable var store: SettingsStore
    let login: LoginItemController
    let connection: ShellConnectionModel
    let sections: ShellSettingsSections
    let export: () -> Void
    private var persistenceMessage: String {
        if let error = store.persistenceError { return error }
        if case .recovered = store.loadStatus { return "设置文件损坏，已保留副本并恢复默认值。修改自动保存。" }
        return "修改自动保存 · 后续功能的偏好将在相应功能上线后使用"
    }
    var body: some View {
        ShellSettingsView(settings: $store.settings, login: login, connection: connection, sections: sections,
                          persistenceMessage: persistenceMessage, exportDiagnostics: export)
            .preferredColorScheme(store.settings.general.appearance == .system ? nil :
                store.settings.general.appearance == .dark ? .dark : .light)
    }
}
