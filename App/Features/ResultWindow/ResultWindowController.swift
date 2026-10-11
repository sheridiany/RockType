import AppKit
import SwiftUI
import RoarkTCore
import RoarkTPlatform
@preconcurrency import ApplicationServices

private final class ResultPanel: NSPanel {
    var acceptsKeyboard = false
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
}

/// Claude's integration point: retain one controller with one dedicated runner.
/// All rectangles accepted by this API use AppKit global screen coordinates.
@MainActor
final class ResultWindowController: NSObject {
    let state: ResultWindowState
    private let panel = ResultPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
    private let settings: () -> AppSettings
    private let feedback: (String) -> Void
    private var running = false
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var safetyTask: Task<Void, Never>?
    private var sourceApp: NSRunningApplication?
    private var sourceWindow: AXUIElement?
    private var sourceChanged = false
    private var anchor: CGRect?

    /// feedback must present an accessible, nonactivating notice after the panel closes.
    /// completed may forward successful results to RecentResults (respect privacy settings).
    init(runner: any OperationRunner, settings: @escaping () -> AppSettings,
         feedback: @escaping (String) -> Void,
         completed: @escaping @MainActor (OperationResult) -> Void = { _ in }) {
        self.settings = settings; self.feedback = feedback
        state = ResultWindowState(runner: runner, readable: { SecureInput.status() == .allowed }, completed: completed)
        super.init()
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.isReleasedWhenClosed = false; panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true
    }

    func start() {
        guard !running else { return }; running = true; state.start()
        panel.contentView = NSHostingView(rootView: LiveResultWindowView(controller: self))
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationChanged),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return false }
                if event.type == .keyDown { return self.handleKey(event) }
                if event.window !== self.panel { self.outsideClick() }
                return false
            }
            return consumed ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.outsideClick() }
        }
    }

    func stop() {
        close(); state.stop(); running = false
        panel.contentView = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }; localMonitor = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }; globalMonitor = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func show(_ request: OperationRequest, toolbarRect: CGRect? = nil) {
        guard SecureInput.status() == .allowed else { feedback("当前输入受保护或无法检查，未打开结果。"); return }
        start(); captureSource(request.session.snapshot.source)
        state.show(request); present(snapshot: request.session.snapshot, toolbarRect: toolbarRect)
    }

    func show(_ result: OperationResult, template: OperationTemplate, toolbarRect: CGRect? = nil) {
        guard SecureInput.status() == .allowed else { feedback("当前输入受保护或无法检查，未打开结果。"); return }
        start(); captureSource(result.session.snapshot.source)
        // A persisted-in-memory result has no retained AX window identity. Never guess a return target.
        sourceChanged = true
        state.show(result, template: template, settings: settings())
        present(snapshot: result.session.snapshot, toolbarRect: toolbarRect)
    }

    func close() {
        safetyTask?.cancel(); safetyTask = nil
        panel.orderOut(nil); panel.acceptsKeyboard = false
        state.clear(); sourceApp = nil; sourceWindow = nil; anchor = nil
    }

    /// Call when settings change. Does not persist content or preferences.
    func applySettings() {
        let selection = settings().selection
        state.pinned = selection.automaticallyPin
        updateWindowStyle()
        if panel.isVisible { placeWindow() }
    }

    func setPinned() { state.pinned.toggle(); updateWindowStyle() }
    func beginQuestion() {
        guard panel.isVisible, state.request != nil, !state.isBusy else { return }
        panel.acceptsKeyboard = true; panel.makeKeyAndOrderFront(nil)
        state.asking = true
    }
    func ask() { state.ask(settings: settings()) }
    func retry() { state.retry(settings: settings()) }
    func escape() {
        if state.isBusy { state.cancel() }
        else if state.asking {
            state.asking = false; panel.makeFirstResponder(nil)
            panel.resignKey(); panel.acceptsKeyboard = false
        } else { close() }
    }

    func copy(original: Bool = false, returning: Bool = false) {
        guard SecureInput.status() == .allowed else { state.notice = "当前输入受保护或无法检查，未复制。"; return }
        let text = original ? state.session?.snapshot.text ?? "" : state.answer
        guard !text.isEmpty else { return }
        do { try Clipboard.shared.writeString(text) }
        catch { state.notice = "复制失败，请重试。"; return }
        guard returning else { state.notice = original ? "原文已复制。" : "结果已复制。"; return }
        let source = sourceApp
        let valid = canReturnToSource()
        close()
        if valid, let source {
            if source.isActive || source.activate(options: []) { feedback("结果已复制，可在来源中粘贴。") }
            else { feedback("结果已复制；无法返回来源，请自行粘贴。") }
        } else { feedback("结果已复制；来源已失效或你已切换应用，请自行粘贴。") }
    }

    private func present(snapshot: ContentSnapshot, toolbarRect: CGRect?) {
        panel.acceptsKeyboard = false; panel.resignKey()
        anchor = toolbarRect ?? snapshot.selectionRect
        updateWindowStyle(); placeWindow(); panel.orderFrontRegardless()
        safetyTask?.cancel()
        safetyTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self else { return }
                if SecureInput.status() != .allowed {
                    self.close(); self.feedback("输入状态无法安全检查，结果窗口已关闭。")
                    return
                }
            }
        }
    }

    private func updateWindowStyle() {
        panel.level = state.pinned ? .floating : .normal
        let opacity = settings().selection.windowOpacity
        panel.alphaValue = opacity.isFinite ? min(1, max(0.3, opacity)) : 1
    }

    private func placeWindow() {
        let point = anchor.map { CGPoint(x: $0.midX, y: $0.midY) } ?? NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = CGSize(width: min(Tokens.Size.resultWidth, max(1, visible.width - 24)),
                          height: min(Tokens.Size.resultMaxHeight, max(1, visible.height - 24)))
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let topScreen = ScreenGeometry.topLeft(visible, primaryHeight: primaryHeight)
        let selection = settings().selection.followToolbar ? anchor.map { ScreenGeometry.topLeft($0, primaryHeight: primaryHeight) } : nil
        let placement = Placement.floating(selection: selection,
                                          cursor: ScreenGeometry.topLeft(NSEvent.mouseLocation, primaryHeight: primaryHeight),
                                          size: size, screen: topScreen)
        let frame = ScreenGeometry.topLeft(CGRect(origin: placement.origin, size: size), primaryHeight: primaryHeight)
        panel.setFrame(frame, display: true)
    }

    private func outsideClick() {
        guard panel.isVisible else { return }
        if settings().selection.automaticallyClose && !state.pinned { close() }
        else {
            state.asking = false; panel.makeFirstResponder(nil)
            panel.resignKey(); panel.acceptsKeyboard = false
        }
    }

    @objc private func applicationChanged(_ notification: Notification) {
        guard panel.isVisible,
              let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if app.processIdentifier != sourceApp?.processIdentifier && app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            sourceChanged = true
            outsideClick()
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.window === panel, panel.isKeyWindow else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let text = event.charactersIgnoringModifiers?.lowercased()
        let editor = panel.firstResponder as? NSTextView
        // Marked text belongs to the input method, including Return and Escape.
        if editor?.hasMarkedText() == true { return false }
        let editingQuestion = state.asking && editor?.isEditable == true
        if event.keyCode == 53 { escape(); return true }
        if text == "l", modifiers == .command { beginQuestion(); return true }
        if event.keyCode == 36 || event.keyCode == 76 {
            if modifiers == .command { copy(returning: true); return true }
            if modifiers.isEmpty && !editingQuestion { copy(returning: true); return true }
        }
        if !editingQuestion, text == "c", modifiers.isEmpty || modifiers == .command { copy(); return true }
        return false
    }

    private func captureSource(_ source: ContentSnapshot.Source) {
        sourceApp = NSRunningApplication(processIdentifier: source.pid)
        sourceWindow = nil
        sourceChanged = sourceApp?.bundleIdentifier != source.bundleID || sourceApp?.isActive != true
        guard !sourceChanged else { return }
        let app = AXUIElementCreateApplication(source.pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        sourceWindow = Self.element(kAXFocusedWindowAttribute, of: app)
    }

    private func canReturnToSource() -> Bool {
        guard !sourceChanged, let sourceApp, !sourceApp.isTerminated, let sourceWindow,
              let source = state.session?.snapshot.source,
              sourceApp.processIdentifier == source.pid, sourceApp.bundleIdentifier == source.bundleID,
              let front = NSWorkspace.shared.frontmostApplication,
              front == sourceApp || front.processIdentifier == ProcessInfo.processInfo.processIdentifier else { return false }
        let app = AXUIElementCreateApplication(source.pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let focused = Self.element(kAXFocusedWindowAttribute, of: app), CFEqual(focused, sourceWindow) else { return false }
        var role: CFTypeRef?
        return AXUIElementCopyAttributeValue(sourceWindow, kAXRoleAttribute as CFString, &role) == .success
    }

    private static func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
