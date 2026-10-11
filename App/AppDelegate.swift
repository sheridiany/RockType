import AppKit
import SwiftUI
import RoarkTCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let gallery = GalleryWindowController()
    private let store = SettingsStore.shared
    private let clock = MenuBarClock()
    private let login = LoginItemController()
    private let connection = ShellConnectionModel()
    private let panel = MenuBarPanelController()
    private let diagnostics = DiagnosticExportController()
    private let permissions = PermissionCenter()
    private lazy var hotkeys = HotkeyCenter(
        read: { [unowned self] in self.store.settings.shortcuts },
        write: { [unowned self] in self.store.settings.shortcuts = $0 },
        showSettings: { [weak self] in self?.showSettings() })
    private lazy var onboarding = OnboardingWindowController(
        store: store,
        permissions: { [unowned self] in AnyView(PermissionCenterView(center: self.permissions)) },
        aiConnection: { [unowned self] in
            AnyView(ShellConnectionView(model: self.connection,
                settings: Binding(get: { self.store.settings.ai }, set: { self.store.settings.ai = $0 })))
        },
        showSettings: { [weak self] in self?.showSettings() })
    private lazy var settingsWindow: SettingsWindowController = {
        let window = SettingsWindowController(store: store, login: login, connection: connection,
            sections: ShellSettingsSections(permissions: permissions, hotkeys: hotkeys,
                showOnboarding: { [weak self] in self?.onboarding.rerun() }))
        window.exportDiagnostics = { [weak self] in self?.diagnostics.export() }
        return window
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.statusImage()
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.setAccessibilityLabel("RoarkT 菜单栏")
        statusItem = item
        clock.didRefresh = { [weak self] in self?.refreshStatus() }
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: SettingsStore.didChange, object: store)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(becameActive),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        installMainMenu()
        login.refresh()
        store.settings.general.launchAtLogin = login.enabled
        connection.refresh(store.settings.ai)
        refreshStatus()
        Task {
            try? await DiagnosticLog.shared.record(.init(action: .settingsLoad,
                status: store.persistenceError == nil ? .succeeded : .failed,
                failure: store.persistenceError == nil ? nil : .storage))
        }
        if CommandLine.arguments.contains("--gallery") {
            gallery.show()
        } else {
            permissions.start()
            hotkeys.start()
        }
        onboarding.applicationDidFinishLaunching()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        onboarding.applicationShouldHandleReopen()
    }

    func applicationWillTerminate(_ notification: Notification) {
        connection.cancel()
        hotkeys.stop()
        permissions.stop()
        clock.stop()
        panel.stop()
        store.flush()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func settingsChanged(_ notification: Notification) {
        connection.refresh(store.settings.ai)
        refreshStatus()
    }

    @objc private func becameActive(_ notification: Notification) {
        guard (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier == ProcessInfo.processInfo.processIdentifier else { return }
        login.refresh()
        if store.settings.general.launchAtLogin != login.enabled { store.settings.general.launchAtLogin = login.enabled }
        connection.refresh(store.settings.ai)
    }

    private func refreshStatus() {
        statusItem?.button?.title = store.settings.general.showBeijingTime ? " 北京 " + clock.beijingTime : ""
        statusItem?.button?.toolTip = "RoarkT · 北京 " + clock.beijingDate + " " + clock.beijingTime
    }

    @objc private func statusClicked() {
        guard let item = statusItem, let button = item.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            panel.close()
            let menu = makeMenu()
            item.menu = menu
            button.performClick(nil)
            item.menu = nil
        } else {
            clock.refresh()
            connection.refresh(store.settings.ai)
            panel.toggle(from: button) {
                LiveMenuRoot(store: store, clock: clock, connection: connection,
                             showSettings: { [weak self] in self?.showSettings() },
                             quit: { NSApp.terminate(nil) })
            }
        }
    }

    @objc func showSettings() { panel.close(); settingsWindow.show() }
    @objc private func showGallery() { panel.close(); gallery.show() }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
        #if DEBUG
        menu.addItem(withTitle: "设计面板…", action: #selector(showGallery), keyEquivalent: "").target = self
        #endif
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 RoarkT", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = makeMenu()
        main.addItem(appItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"),
                                       ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    /// Vector template R glyph stays crisp in both menu-bar appearances.
    private static func statusImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let font = NSFont.systemFont(ofSize: 17, weight: .semibold)
            let text = NSAttributedString(string: "R", attributes: [.font: font, .foregroundColor: NSColor.black])
            let size = text.size()
            text.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "RoarkT"
        return image
    }
}

private struct LiveMenuRoot: View {
    let store: SettingsStore
    let clock: MenuBarClock
    let connection: ShellConnectionModel
    let showSettings: () -> Void
    let quit: () -> Void
    var body: some View {
        ShellMenuBarPanel(clock: clock, showClock: store.settings.general.showBeijingTime,
                          aiStatus: connection.testing ? "AI 测试中" :
                            connection.results.prefix(2).allSatisfy({ $0 == "可用" }) ? "AI 文字/流式可用" :
                            connection.configured ? "AI 已配置 · 待验证" : "AI 未配置",
                          showSettings: showSettings, quit: quit)
            .preferredColorScheme(store.settings.general.appearance == .system ? nil :
                store.settings.general.appearance == .dark ? .dark : .light)
    }
}
