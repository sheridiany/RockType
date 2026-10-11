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
final class ResultWindowController: NSObject, NSWindowDelegate {
    let state: ResultWindowState
    private let panel = ResultPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .resizable],
                                    backing: .buffered, defer: false)
    private let settings: () -> AppSettings
    private let feedback: @MainActor (String) -> Void
    private var running = false
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var safetyTask: Task<Void, Never>?
    private var source: OperationSource?
    private let readable: @MainActor () -> Bool
    private let aiConfigured: @MainActor () -> Bool
    private var sourceChanged = false
    private var anchor: CGRect?
    private var initialRetryUnavailable: String?
    private let geometry: ResultWindowGeometry
    private var placing = false
    private var userPlaced = false
    private var lastAutomaticPin = false

    /// feedback must present an accessible, nonactivating notice after the panel closes.
    /// completed may forward successful results to RecentResults (respect privacy settings).
    init(runner: any OperationRunner, settings: @escaping () -> AppSettings,
         feedback: @escaping @MainActor (String) -> Void,
         completed: @escaping @MainActor (OperationResult) -> Void = { _ in },
         readable: @escaping @MainActor () -> Bool = { SecureInput.status() == .allowed },
         aiConfigured: @escaping @MainActor () -> Bool = { true },
         geometry: ResultWindowGeometry = .shared) {
        self.settings = settings; self.feedback = feedback; self.geometry = geometry
        lastAutomaticPin = settings().selection.automaticallyPin
        self.readable = readable; self.aiConfigured = aiConfigured
        state = ResultWindowState(runner: runner, readable: readable, completed: completed, feedback: feedback)
        super.init()
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.isReleasedWhenClosed = false; panel.isMovableByWindowBackground = false
        panel.delegate = self
        panel.minSize = CGSize(width: 340, height: 300)
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
                else if event.type == .leftMouseDown, self.readable() {
                    // Explicit interaction may focus selectable text; merely presenting never does.
                    self.panel.acceptsKeyboard = true
                    self.panel.makeKey()
                }
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

    func show(_ request: OperationRequest, source: OperationSource? = nil, toolbarRect: CGRect? = nil) {
        guard readable() else { feedback("当前输入受保护或无法检查，未打开结果。"); return }
        start(); self.source = source; sourceChanged = false
        initialRetryUnavailable = nil
        state.show(request); present(snapshot: request.session.snapshot, toolbarRect: toolbarRect)
    }

    func show(_ result: OperationResult, template: OperationTemplate, toolbarRect: CGRect? = nil,
              initialRetryUnavailable: String? = nil) {
        guard readable() else { feedback("当前输入受保护或无法检查，未打开结果。"); return }
        start(); source = nil
        // A persisted-in-memory result has no retained AX window identity. Never guess a return target.
        sourceChanged = true
        self.initialRetryUnavailable = initialRetryUnavailable
        state.show(result, template: template, settings: settings())
        if let initialRetryUnavailable { state.notice = initialRetryUnavailable }
        present(snapshot: result.session.snapshot, toolbarRect: toolbarRect)
    }

    func close() {
        safetyTask?.cancel(); safetyTask = nil
        panel.orderOut(nil); panel.acceptsKeyboard = false
        state.stop(); source = nil; anchor = nil; initialRetryUnavailable = nil
    }

    /// Call when settings change. Does not persist content or preferences.
    func applySettings() {
        let selection = settings().selection
        if lastAutomaticPin != selection.automaticallyPin {
            state.pinned = selection.automaticallyPin
            lastAutomaticPin = selection.automaticallyPin
        }
        updateWindowStyle()
        if panel.isVisible, !userPlaced { placeWindow() }
    }

    func setPinned() { state.pinned.toggle(); updateWindowStyle() }
    func beginQuestion() {
        guard panel.isVisible, state.request != nil, state.canAsk, readable() else { return }
        guard aiConfigured() else { feedback("请前往设置配置 AI 连接后追问。"); return }
        panel.acceptsKeyboard = true; panel.makeKeyAndOrderFront(nil)
        state.asking = true
    }
    func ask() {
        guard readable() else { close(); return }
        guard aiConfigured() else { feedback("请前往设置配置 AI 连接后追问。"); return }
        state.ask(settings: settings())
    }
    func retry() {
        guard readable() else { close(); return }
        if let initialRetryUnavailable, state.request?.session.turns.isEmpty == true {
            state.notice = initialRetryUnavailable
            return
        }
        var current = settings()
        if !aiConfigured() {
            guard state.request?.template.id == "translate", state.request?.question == nil else {
                feedback("请前往设置配置 AI 连接后重试。"); return
            }
            current.translation.engine = .offlineFirst
        }
        state.retry(settings: current)
    }
    func escape() {
        if state.isBusy { state.cancel() }
        else if state.asking {
            state.asking = false; panel.makeFirstResponder(nil)
            panel.resignKey(); panel.acceptsKeyboard = false
        } else { close() }
    }

    func copy(original: Bool = false, returning: Bool = false) {
        guard readable() else { feedback("当前输入受保护或无法检查，未复制。"); return }
        let text = original ? state.session?.snapshot.text ?? "" : state.answer
        guard !text.isEmpty else { return }
        do { try Clipboard.shared.writeString(text) }
        catch { feedback("复制失败，请重试。"); return }
        guard returning else { state.notice = original ? "原文已复制。" : "结果已复制。"; return }
        let returnSource = source
        let shouldReturn = !sourceChanged
        close()
        switch shouldReturn ? returnSource?.returnToSource() ?? .unavailable : .unavailable {
        case .window: feedback("结果已复制，可在来源中粘贴。")
        case .application: feedback("结果已复制；原窗口不可用，已返回来源应用，请自行选择粘贴位置。")
        case .unavailable: feedback("结果已复制；来源已失效或你已切换应用，请自行粘贴。")
        }
    }

    private func present(snapshot: ContentSnapshot, toolbarRect: CGRect?) {
        panel.acceptsKeyboard = false; panel.resignKey()
        anchor = toolbarRect ?? snapshot.selectionRect
        userPlaced = false
        updateWindowStyle(); placeWindow(); panel.orderFrontRegardless()
        safetyTask?.cancel()
        safetyTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self else { return }
                if !self.readable() {
                    self.close(); self.feedback("输入状态无法安全检查，结果窗口已关闭。")
                    return
                }
            }
        }
    }

    var isVisible: Bool { panel.isVisible }

    private func updateWindowStyle() {
        switch settings().general.appearance {
        case .system: panel.appearance = nil
        case .light: panel.appearance = NSAppearance(named: .aqua)
        case .dark: panel.appearance = NSAppearance(named: .darkAqua)
        }
        panel.level = state.pinned ? .floating : .normal
        let opacity = settings().selection.windowOpacity
        panel.alphaValue = opacity.isFinite ? min(1, max(0.3, opacity)) : 1
    }

    private func placeWindow() {
        placing = true
        defer { placing = false }
        if !settings().selection.followToolbar, let remembered = geometry.frame,
           let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(remembered) }) ?? NSScreen.main {
            panel.setFrame(avoidingOtherResults(remembered, screen: screen.visibleFrame), display: true)
            return
        }
        let point = anchor.map { CGPoint(x: $0.midX, y: $0.midY) } ?? NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = CGSize(width: min(geometry.frame?.width ?? Tokens.Size.resultWidth, max(1, visible.width - 24)),
                          height: min(geometry.frame?.height ?? Tokens.Size.resultMaxHeight, max(1, visible.height - 24)))
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let topScreen = ScreenGeometry.topLeft(visible, primaryHeight: primaryHeight)
        let selection = settings().selection.followToolbar ? anchor.map { ScreenGeometry.topLeft($0, primaryHeight: primaryHeight) } : nil
        let placement = Placement.floating(selection: selection,
                                          cursor: ScreenGeometry.topLeft(NSEvent.mouseLocation, primaryHeight: primaryHeight),
                                          size: size, screen: topScreen)
        let frame = ScreenGeometry.topLeft(CGRect(origin: placement.origin, size: size), primaryHeight: primaryHeight)
        panel.setFrame(avoidingOtherResults(frame, screen: visible), display: true)
    }

    private func avoidingOtherResults(_ frame: CGRect, screen: CGRect) -> CGRect {
        let occupied = NSApplication.shared.windows.compactMap { $0 as? ResultPanel }
            .filter { $0 !== panel && $0.isVisible }.map(\.frame)
        return ResultWindowGeometry.avoiding(frame, occupied: occupied, screen: screen)
    }

    func windowDidMove(_ notification: Notification) { rememberGeometry() }
    func windowDidResize(_ notification: Notification) { rememberGeometry() }
    private func rememberGeometry() {
        guard !placing, panel.isVisible else { return }
        userPlaced = true
        geometry.remember(panel.frame)
    }
    func copyCode(_ text: String) {
        guard readable(), !text.isEmpty else { return }
        do { try Clipboard.shared.writeString(text); state.notice = "代码已复制。" }
        catch { state.notice = "复制失败，请重试。" }
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
        if app.processIdentifier != source?.pid && app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            sourceChanged = true
            outsideClick()
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.window === panel, panel.isKeyWindow else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let text = event.charactersIgnoringModifiers?.lowercased()
        let editor = panel.firstResponder as? NSTextView
        let action = ResultWindowKeyAction.resolve(code: event.keyCode, text: text, modifiers: modifiers,
            editingQuestion: state.asking && editor?.isEditable == true, markedText: editor?.hasMarkedText() == true)
        switch action {
        case .passThrough: return false
        case .escape: escape()
        case .ask: beginQuestion()
        case .send: ask()
        case .copy: copy()
        case .copyAndReturn: copy(returning: true)
        }
        return true
    }
}
