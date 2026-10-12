import AppKit
import Observation
import RoarkTCore
import RoarkTPlatform

/// Claude's integration owns result windows / search dispatch and the existing HotkeyCenter.
/// Call start/stop with App lifecycle; forward translate/summarize hotkeys to trigger(_:).
@MainActor final class SelectionController: NSObject {
    private let settings: @MainActor () -> AppSettings
    private let perform: @MainActor (OperationRequest, OperationSource?, CGRect?) -> Void
    private let search: @MainActor (ContentSnapshot, AppSettings) -> Void
    private let notice: @MainActor (String) -> Void
    private let aiConfigured: @MainActor () -> Bool
    private let allowed: @MainActor () -> Bool
    private let capture: SelectionCapture
    private let toolbar = SelectionToolbarWindow()
    private var running = false
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var pending: Task<Void, Never>?
    private var protectionTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var observationGeneration: UInt64 = 0
    private var selection: CapturedSelection?
    private var pendingIsShortcut = false
    private var gesture = SelectionGesture()

    init(settings: @escaping @MainActor () -> AppSettings,
         perform: @escaping @MainActor (OperationRequest, OperationSource?, CGRect?) -> Void,
         search: @escaping @MainActor (ContentSnapshot, AppSettings) -> Void,
         notice: @escaping @MainActor (String) -> Void,
         aiConfigured: @escaping @MainActor () -> Bool = { true },
         allowed: @escaping @MainActor () -> Bool = { SecureInput.status() == .allowed },
         capture: SelectionCapture = SelectionCapture()) {
        self.settings = settings; self.perform = perform; self.search = search
        self.notice = notice; self.capture = capture; self.aiConfigured = aiConfigured; self.allowed = allowed
        super.init()
    }

    func start() {
        guard !running else { return }
        running = true
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                             .rightMouseDown, .otherMouseDown, .keyDown, .flagsChanged, .scrollWheel]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, local: false) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, local: true) }
            return event
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sourceChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sourceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sourceChanged),
            name: NSWorkspace.willSleepNotification, object: nil)
        observeSettings()
        // Inspect protection only while visible; never poll the clipboard or selected text.
        protectionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                guard let self, self.running else { return }
                if self.toolbar.isVisible, !self.allowed() || self.selection?.isCurrent() != true { self.dismiss() }
            }
        }
        if globalMonitor == nil { notice("划词监听不可用，请检查辅助功能权限；仍可使用选区快捷键。") }
    }

    func stop() {
        running = false
        observationGeneration &+= 1
        dismiss()
        protectionTask?.cancel(); protectionTask = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil; globalMonitor = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Registration / conflict reporting stays in HotkeyCenter; no second Carbon registration.
    func trigger(_ action: ShortcutAction) {
        guard running else { return }
        switch action {
        case .translateSelection: beginCapture(action: "translate")
        case .summarizeSelection: beginCapture(action: "summarize")
        default: break
        }
    }

    func triggerTemplate(_ id: String) {
        guard running else { return }; beginCapture(action: id)
    }

    func dismiss(resetGesture: Bool = true) {
        generation &+= 1
        pending?.cancel(); pending = nil
        selection = nil
        pendingIsShortcut = false
        if resetGesture { gesture = SelectionGesture() }
        toolbar.hide()
    }

    @objc private func sourceChanged(_ notification: Notification) { dismiss() }

    private func observeSettings() {
        guard running else { return }
        observationGeneration &+= 1
        let observed = observationGeneration
        _ = withObservationTracking { settings() } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.observationGeneration == observed else { return }
                self.dismiss()
                self.observeSettings()
            }
        }
    }

    private func handle(_ event: NSEvent, local: Bool) {
        guard running else { return }
        if local, toolbar.contains(event.window), event.type != .keyDown, event.type != .flagsChanged { return }
        if Clipboard.isSelectionCopyEvent(event.cgEvent) { return }
        // Carbon and the global monitor can deliver the same shortcut in either order.
        // Releasing its modifiers must not cancel an asynchronous copy fallback.
        if event.type == .keyDown, isSelectionShortcut(event) { return }
        if event.type == .flagsChanged, pendingIsShortcut { return }
        switch event.type {
        case .leftMouseDown:
            dismiss()
            if !local { gesture.begin(modifiers: event.modifierFlags,
                suppress: settings().selection.suppressAccidentalPopups ?? true) }
        case .leftMouseDragged:
            gesture.drag(modifiers: event.modifierFlags)
        case .leftMouseUp:
            let selected = gesture.finish(clickCount: event.clickCount, modifiers: event.modifierFlags)
            if !local, selected, settings().selection.trigger == .selection { beginCapture(action: nil) }
        case .scrollWheel:
            gesture.scroll()
            dismiss(resetGesture: false)
        case .flagsChanged:
            gesture.modifiersChanged(event.modifierFlags)
            dismiss(resetGesture: false)
        case .rightMouseDown, .otherMouseDown, .keyDown: dismiss()
        default: break
        }
    }

    private func isSelectionShortcut(_ event: NSEvent) -> Bool {
        guard let key = GlobalHotkeys.key(forPhysicalCode: event.keyCode) else { return false }
        var modifiers: Shortcut.Modifiers = []
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        return [ShortcutAction.translateSelection, .summarizeSelection].contains { action in
            guard let shortcut = settings().shortcuts.bindings[action] else { return false }
            return shortcut.key?.lowercased() == key && shortcut.modifiers == modifiers
        }
    }

    private func beginCapture(action: String?) {
        dismiss()
        let currentSettings = settings()
        guard allowed() else {
            if action != nil { notice("无法读取选区，请检查辅助功能权限和安全输入状态。") }
            return
        }
        guard let app = Accessibility.frontmostApplication,
              app.pid != ProcessInfo.processInfo.processIdentifier,
              SelectionPolicy.permits(app.bundleID, settings: currentSettings.selection) else { return }
        let requestGeneration = generation
        pendingIsShortcut = action != nil
        pending = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // Mouse-up delivery can precede AX's selection update. Shortcuts capture immediately.
                if action == nil { try await Task.sleep(for: .milliseconds(90)) }
                let captured = try await self.capture.capture()
                try Task.checkCancellation()
                guard self.running, self.generation == requestGeneration, self.allowed(), captured.isCurrent(),
                      captured.snapshot.source.pid == app.pid,
                      SelectionPolicy.permits(captured.snapshot.source.bundleID, settings: self.settings().selection) else { return }
                self.pending = nil
                self.pendingIsShortcut = false
                self.selection = captured
                if let action { self.invoke(action, fromToolbar: false) }
                else {
                    guard self.settings().selection.trigger == .selection,
                          SelectionGesture.permitsText(captured.snapshot.text,
                            suppress: self.settings().selection.suppressAccidentalPopups ?? true) else { self.dismiss(); return }
                    self.toolbar.show(snapshot: captured.snapshot, settings: self.settings(), aiConfigured: self.aiConfigured()) { [weak self] in
                        self?.invoke($0, fromToolbar: true)
                    }
                }
            } catch is CancellationError {
                // A newer gesture owns presentation.
            } catch {
                guard self.generation == requestGeneration else { return }
                self.pending = nil
                self.pendingIsShortcut = false
                if action != nil { self.notice("未能取得选中文字，请重新选择并检查辅助功能权限。") }
            }
        }
    }

    private func invoke(_ action: String, fromToolbar: Bool) {
        guard let captured = selection else { return }
        performAction(action, captured: captured, fromToolbar: fromToolbar)
    }

    func performAction(_ action: String, captured: CapturedSelection, fromToolbar: Bool) {
        guard captured.isCurrent(), allowed() else { dismiss(); return }
        var currentSettings = settings()
        guard SelectionPolicy.permits(captured.snapshot.source.bundleID, settings: currentSettings.selection),
              !fromToolbar || SelectionPolicy.actions(settings: currentSettings).contains(action) else { dismiss(); return }
        let snapshot = captured.snapshot
        let toolbarRect = fromToolbar ? toolbar.frame : nil
        dismiss()
        if action == "copy" {
            do { try Clipboard.shared.writeString(snapshot.text) }
            catch { notice("无法复制，请重试。") }
        } else if action == "search" {
            search(snapshot, currentSettings)
        } else if let template = currentSettings.templates.first(where: { $0.id == action && $0.input == .text }) {
            guard aiConfigured() || template.id == "translate" else {
                notice("请先前往设置配置 AI 连接，再使用解释、总结、润色或自定义操作。")
                return
            }
            if !aiConfigured() { currentSettings.translation.engine = .offlineFirst }
            perform(.init(session: .init(snapshot: snapshot), template: template, settings: currentSettings),
                    captured.returnSource, toolbarRect)
        } else {
            notice("此操作模板不可用，请检查操作模板设置。")
        }
    }

    isolated deinit {
        pending?.cancel(); protectionTask?.cancel()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        toolbar.hide()
    }
}
