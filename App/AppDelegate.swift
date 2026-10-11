import AppKit
import SwiftUI
import RoarkTCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    #if DEBUG
    private let gallery = GalleryWindowController()
    #endif
    private let store = SettingsStore.shared
    private let clock = MenuBarClock()
    private let login = LoginItemController()
    private let connection = ShellConnectionModel()
    private let panel = MenuBarPanelController()
    private let diagnostics = DiagnosticExportController()
    private let permissions = PermissionCenter()
    private let noticeController = TransientNoticeController()
    private lazy var inputAI = InputAIController(store: store)
    private lazy var voice = VoiceInputController(store: store)
    private lazy var screenshot: ScreenshotCoordinator = {
        let coordinator = ScreenshotCoordinator()
        coordinator.readSettings = { [unowned self] in self.store.settings }
        coordinator.onNotice = { [weak self] in self?.noticeController.show(message: $0) }
        coordinator.onPermissionRequired = { [weak self] in
            self?.panel.close()
            self?.noticeController.show(message: "截图需要屏幕录制权限。授权后请重新按下截图快捷键。")
            self?.permissions.openSettings(.screenRecording)
        }
        coordinator.configureVision = { [weak self] in
            self?.panel.close(); self?.settingsWindow.show(section: .ai)
        }
        coordinator.imageCapabilityVerified = { [weak self] config, model in
            guard let self else { return false }
            return self.connection.imageCapabilityVerified(connection: config, model: model)
        }
        coordinator.performText = { [weak self] request in
            self?.operations.perform(request, source: nil, toolbarRect: nil)
        }
        coordinator.imageCompleted = { [weak self] result, template in
            self?.operations.presentCompleted(result, template: template)
        }
        return coordinator
    }()
    private let operationsEnvironment = OperationsEnvironment()
    private lazy var operations = SelectionOperationsController(
        environment: operationsEnvironment, settings: { [unowned self] in self.store.settings },
        aiConfigured: { [unowned self] in AIProviderAvailability.configured(self.store.settings) },
        notice: { [weak self] in self?.noticeController.show(message: $0) })
    private lazy var selectionController = SelectionController(
        settings: { [unowned self] in self.store.settings },
        perform: { [weak self] request, source, rect in self?.operations.perform(request, source: source, toolbarRect: rect) },
        search: { [weak self] in self?.operations.search($0, settings: $1) },
        notice: { [weak self] in self?.noticeController.show(message: $0) },
        aiConfigured: { [unowned self] in AIProviderAvailability.configured(self.store.settings) })
    private lazy var hotkeys = HotkeyCenter(
        read: { [unowned self] in self.store.settings.shortcuts },
        write: { [unowned self] in self.store.settings.shortcuts = $0 },
        showSettings: { [weak self] in self?.showSettings() },
        unavailableAction: { [weak self] in self?.noticeController.show($0) },
        selection: { [weak self] in self?.selectionController.trigger($0) },
        voiceListening: { [weak self] enabled in
            guard let self else { return false }
            self.voice.stop()
            if enabled { self.voice.start() }
            let available = !enabled || self.voice.monitoringAvailable
            if !available { self.voice.stop() }
            return available
        })
    private lazy var settingsWindow: SettingsWindowController = {
        let window = SettingsWindowController(store: store, login: login, connection: connection,
            sections: ShellSettingsSections(permissions: permissions, hotkeys: hotkeys))
        window.clearCurrentContent = { [weak self] in self?.clearCurrentContent() }
        window.exportDiagnostics = { [weak self] in self?.diagnostics.export() }
        return window
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The design gallery has no production listeners, preference writes or permission requests.
    #if DEBUG
        if CommandLine.arguments.contains("--gallery") { gallery.show(); return }
    #endif
        updateStatusItemVisibility()
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
        inputAI.start()
        permissions.start()
        operationsEnvironment.start()
        selectionController.start()
        PinnedImageController.shared.setHistoryLimit(store.settings.screenshot.pinHistoryLimit ?? 10)
        screenshot.start()
        hotkeys.screenshotAction = { [weak self] in self?.captureScreenshot() }
        hotkeys.start()
        if SettingsLaunchPolicy.action(arguments: CommandLine.arguments) == .settings { showSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    #if DEBUG
        if CommandLine.arguments.contains("--gallery") { gallery.show(); return false }
    #endif
        showSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
    #if DEBUG
        if CommandLine.arguments.contains("--gallery") { clock.stop(); panel.stop(); return }
    #endif
        inputAI.stop()
        connection.cancel()
        hotkeys.stop()
        voice.stop()
        screenshot.stop()
        selectionController.stop()
        operations.stop()
        operationsEnvironment.stop()
        noticeController.stop()
        permissions.stop()
        clock.stop()
        panel.stop()
        store.flush()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func settingsChanged(_ notification: Notification) {
        PinnedImageController.shared.setHistoryLimit(store.settings.screenshot.pinHistoryLimit ?? 10)
        connection.refresh(store.settings.ai)
        operations.settingsChanged()
        refreshStatus()
    }

    @objc private func becameActive(_ notification: Notification) {
        guard (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier == ProcessInfo.processInfo.processIdentifier else { return }
        login.refresh()
        if store.settings.general.launchAtLogin != login.enabled { store.settings.general.launchAtLogin = login.enabled }
        connection.refresh(store.settings.ai)
    }

    /// The menu bar item is opt-in (settings → general); no item means no menu bar presence at all.
    private func updateStatusItemVisibility() {
        if store.settings.general.showsMenuBarItem {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = Self.statusImage()
            item.button?.imagePosition = .imageLeading
            item.button?.target = self
            item.button?.action = #selector(statusClicked)
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            item.button?.setAccessibilityLabel("RockType 菜单栏")
            statusItem = item
        } else if let item = statusItem {
            panel.close()
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func refreshStatus() {
        updateStatusItemVisibility()
        statusItem?.button?.title = store.settings.general.showBeijingTime ? " 北京 " + clock.beijingTime : ""
        statusItem?.button?.toolTip = "RockType · 北京 " + clock.beijingDate + " " + clock.beijingTime
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
                LiveMenuRoot(screenshot: screenshot, capture: { [weak self] in self?.captureScreenshot() }, store: store, clock: clock, connection: connection, recent: operationsEnvironment.recent,
                             reopen: { [weak self] result in self?.panel.close(); self?.operations.reopen(result) },
                             clear: { [weak self] in self?.clearCurrentContent() },
                             prepareImageAction: { [weak self] in self?.panel.close() },
                             restorePin: { [weak self] in self?.restorePinnedImage() },
                             exitPinPassthrough: { [weak self] in self?.exitPinnedPassthrough() },
                             showSettings: { [weak self] in self?.showSettings() },
                             quit: { NSApp.terminate(nil) })
            }
        }
    }

    private func clearCurrentContent() {
        screenshot.cancel()
        screenshot.closePreview()
        PinnedImageController.shared.closeAll()
        selectionController.dismiss()
        operations.clearCurrentContent()
        noticeController.show(message: "当前内容已清除。")
    }

    @objc private func captureScreenshot() { panel.close(); screenshot.capture() }

    @objc private func restorePinnedImage() {
        panel.close()
        if !PinnedImageController.shared.restoreLast() { noticeController.show(message: "暂无可恢复的贴图，或安全输入保护已开启。") }
    }
    @objc private func exitPinnedPassthrough() {
        panel.close(); PinnedImageController.shared.exitMousePassthrough()
    }
    @objc private func recognizeClipboardImage() { panel.close(); screenshot.openClipboardImage(recognize: true) }
    @objc private func previewClipboardImage() { panel.close(); screenshot.openClipboardImage() }
    @objc private func recognizeImageFiles() { panel.close(); screenshot.openImageFiles() }

    @objc func showSettings() { panel.close(); settingsWindow.show() }
    #if DEBUG
    @objc private func showGallery() { panel.close(); gallery.show() }
    #endif

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "截图", action: #selector(captureScreenshot), keyEquivalent: "").target = self
        for (title, action) in [
            ("找回最近关闭的贴图", #selector(restorePinnedImage)),
            ("退出贴图鼠标穿透", #selector(exitPinnedPassthrough)),
            ("识别剪贴板图片", #selector(recognizeClipboardImage)),
            ("预览剪贴板图片", #selector(previewClipboardImage)),
            ("批量识别图片…", #selector(recognizeImageFiles))
        ] { menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self }
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
        #if DEBUG
        menu.addItem(withTitle: "设计面板…", action: #selector(showGallery), keyEquivalent: "").target = self
        #endif
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 RockType", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        image.accessibilityDescription = "RockType"
        return image
    }
}

private struct LiveMenuRoot: View {
    let screenshot: ScreenshotCoordinator
    let capture: () -> Void
    let store: SettingsStore
    let clock: MenuBarClock
    let connection: ShellConnectionModel
    let recent: InMemoryRecentResults
    let reopen: (OperationResult) -> Void
    let clear: () -> Void
    let prepareImageAction: () -> Void
    let restorePin: () -> Void
    let exitPinPassthrough: () -> Void
    let showSettings: () -> Void
    let quit: () -> Void
    var body: some View {
        ShellMenuBarPanel(clock: clock, showClock: store.settings.general.showBeijingTime,
                          aiStatus: connection.testing ? "AI 测试中" :
                            connection.results.prefix(2).allSatisfy({ $0 == "可用" }) ? "AI 文字/流式可用" :
                            connection.configured ? "AI 已配置 · 待验证" : "AI 未配置",
                          recent: recent.results, reopen: reopen, clear: clear, screenshot: screenshot, capture: capture,
                          pinHistoryCount: PinnedImageController.shared.history.entries.count, restorePin: restorePin,
                          hasPassthroughPins: PinnedImageController.shared.panels.contains { $0.ignoresMouseEvents },
                          exitPinPassthrough: exitPinPassthrough, prepareImageAction: prepareImageAction,
                          showSettings: showSettings, quit: quit)
            .preferredColorScheme(store.settings.general.appearance == .system ? nil :
                store.settings.general.appearance == .dark ? .dark : .light)
    }
}
