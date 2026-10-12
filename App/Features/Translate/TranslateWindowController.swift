import AppKit
import SwiftUI
import RoarkTCore
import RoarkTPlatform

private final class TranslatePanel: NSPanel {
    var acceptsEditing = false
    override var canBecomeKey: Bool { acceptsEditing }
    override var canBecomeMain: Bool { false }
}

@MainActor final class TranslateWindowController: NSObject, NSWindowDelegate {
    let state: TranslateWindowState
    private let panel = TranslatePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
    private let settings: () -> AppSettings
    private let allowed: () -> Bool
    private let feedback: @MainActor (String) -> Void
    private let defaults: UserDefaults?
    private var source: OperationSource?
    private var replacement: SourceReplacement?
    private var sourceChanged = false
    private var monitor: Any?
    private var watch: Task<Void, Never>?
    private var placing = false
    private var naturalHeight: CGFloat = 240
    private var manualHeightLimit: CGFloat?
    private var anchor: CGRect?
    var slots = TranslateWindowSlots()
    var onClose: () -> Void = {}
    var isVisible: Bool { panel.isVisible }
    var windowFrame: CGRect { panel.frame }
    var isSourceFocused: Bool { panel.isKeyWindow && panel.firstResponder is TranslateSourceEditor.Editor }

    init(request: OperationRequest, runner: any OperationRunner, settings: @escaping () -> AppSettings,
         rememberTarget: @escaping (String) -> Void = { _ in },
         allowed: @escaping @MainActor () -> Bool = { SecureInput.status() == .allowed },
         completed: @escaping @MainActor (OperationResult) -> Void = { _ in }, defaults: UserDefaults? = .standard, feedback: @escaping @MainActor (String) -> Void = { _ in },
         wordLookup: WordLookup? = nil, sourceSpeaker: TextSpeaker? = nil, translationSpeaker: TextSpeaker? = nil) {
        self.settings = settings; self.allowed = allowed; self.defaults = defaults; self.feedback = feedback
        if let height = defaults?.object(forKey: "translateWindowHeightLimit") as? Double,
           height.isFinite, height >= TranslateWindowLayout.minimumHeight { manualHeightLimit = height }
        state = TranslateWindowState(request: request, runner: runner, settings: settings, rememberTarget: rememberTarget, allowed: allowed, completed: completed, feedback: feedback, wordLookup: wordLookup, sourceSpeaker: sourceSpeaker, translationSpeaker: translationSpeaker)
        super.init()
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false; panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 360, height: TranslateWindowLayout.minimumHeight); panel.delegate = self
    }
    func show(source: OperationSource?, anchor: CGRect?, focus: Bool = false, completed: OperationResult? = nil) {
        guard allowed() else { return }
        self.source = source; self.anchor = anchor; sourceChanged = source == nil
        let replacement = SourceReplacement(source: source, snapshot: state.originSnapshot)
        self.replacement = replacement
        slots.replacement = { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(SourceReplacementButton(replacement: replacement, text: self.state.result.answer,
                enabled: self.state.result.phase == .done && self.state.result.currentQuestion == nil, compact: true,
                feedback: { [weak self] in self?.state.result.notice = $0 }))
        }
        panel.contentView = NSHostingView(rootView: TranslateWindowView(state: state, close: { [weak self] in self?.close() },
            focusEditor: { [weak self] in self?.activateEditing() }, copy: { [weak self] in self?.copy(original: $0, returning: $1) }, slots: slots, copyCode: { [weak self] in self?.copyCode($0) },
            contentHeight: { [weak self] in self?.naturalHeight = $0 }))
        applyAppearance()
        place(initial: true)
        panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || focus ? 1 : 0
        panel.orderFrontRegardless()
        if panel.alphaValue == 0 { NSAnimationContext.runAnimationGroup { context in context.duration = 0.12; panel.animator().alphaValue = 1 } }
        state.start(translate: completed == nil && !state.original.isEmpty)
        if let completed { state.showCompleted(completed) }
        if focus { focusSource() }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel, self.panel.isKeyWindow else { return event }
            return self.handle(event) ? nil : event
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        watch = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self else { return }
                guard self.allowed() else { self.close(); self.feedback("当前输入受保护或无法检查，翻译窗已关闭。"); return }
                self.replacement?.refresh()
                self.place(initial: false)
            }
        }
    }
    func close() {
        watch?.cancel(); watch = nil
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        replacement?.stop(); replacement = nil; slots.replacement = { AnyView(EmptyView()) }
        state.stop(); slots.close(); panel.orderOut(nil); panel.contentView = nil; panel.acceptsEditing = false
        source = nil; onClose()
    }
    func activateEditing() { guard allowed() else { return }; panel.acceptsEditing = true; panel.makeKey() }
    func focusSource() {
        panel.contentView?.layoutSubtreeIfNeeded()
        activateEditing()
        func find(_ view: NSView) -> TranslateSourceEditor.Editor? {
            if let editor = view as? TranslateSourceEditor.Editor { return editor }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        if let content = panel.contentView, let editor = find(content) { panel.makeFirstResponder(editor) }
    }
    func copy(original: Bool, returning: Bool) {
        guard allowed() else { return }
        let text = original ? state.original : state.result.answer
        guard !text.isEmpty else { return }
        do { try Clipboard.shared.writeString(text) }
        catch { state.result.notice = "复制未完成，请重试。"; return }
        if returning {
            let destination = source, canReturn = !sourceChanged
            close()
            if canReturn { _ = destination?.returnToSource() }
        } else { state.result.notice = original ? "原文已复制。" : "译文已复制。" }
    }
    private func copyCode(_ text: String) {
        guard allowed(), !text.isEmpty else { return }
        do { try Clipboard.shared.writeString(text); state.result.notice = "代码已复制。" }
        catch { state.result.notice = "复制未完成，请重试。" }
    }
    private func handle(_ event: NSEvent) -> Bool {
        let editor = panel.firstResponder as? NSTextView
        guard editor?.hasMarkedText() != true else { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        if event.keyCode == 53 { close(); return true }
        guard flags == .command else { return false }
        switch event.keyCode {
        case 8:
            if editor?.isEditable == true && (editor?.selectedRange().length ?? 0) > 0 { return false }
            copy(original: false, returning: false)
        case 36: copy(original: false, returning: true)
        case 15: state.submit()
        case 37: state.swap()
        default: return false
        }
        return true
    }
    @objc private func applicationChanged(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if app.processIdentifier != source?.pid && app.processIdentifier != ProcessInfo.processInfo.processIdentifier { sourceChanged = true; replacement?.invalidate() }
    }
    private func applyAppearance() {
        switch settings().general.appearance {
        case .system: panel.appearance = nil
        case .light: panel.appearance = NSAppearance(named: .aqua)
        case .dark: panel.appearance = NSAppearance(named: .darkAqua)
        }
    }
    static func fittedSize(_ requested: CGSize, screen: CGRect) -> CGSize {
        CGSize(width: min(max(360, requested.width), max(1, screen.width - 24)),
               height: min(max(TranslateWindowLayout.minimumHeight, requested.height), max(1, screen.height * 0.6)))
    }
    private func place(initial: Bool) {
        let point = anchor.map { CGPoint(x: $0.midX, y: $0.midY) } ?? NSEvent.mouseLocation
        guard let screen = (initial ? nil : panel.screen)
                ?? NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        let available = screen.visibleFrame
        let saved = defaults?.array(forKey: "translateWindowFrame") as? [Double]
        let validSaved = saved?.count == 4 && saved?.allSatisfy(\.isFinite) == true
        // Saved width/position are retained. A manually chosen height is a ceiling, not empty space.
        let desired = min(naturalHeight, manualHeightLimit ?? .greatestFiniteMagnitude)
        let size = Self.fittedSize(CGSize(width: validSaved ? saved![2] : 420, height: desired), screen: available)
        if !initial && abs(size.height - panel.frame.height) < 1 && abs(size.width - panel.frame.width) < 1 { return }
        var frame = CGRect(x: initial ? point.x - size.width / 2 : panel.frame.minX,
                           y: initial ? point.y - size.height - 12 : panel.frame.maxY - size.height,
                           width: size.width, height: size.height)
        if initial && validSaved { frame.origin = CGPoint(x: saved![0], y: saved![1]) }
        placing = true
        panel.maxSize = CGSize(width: available.width - 24, height: available.height * 0.6)
        panel.setFrame(ResultWindowGeometry.fitted(frame, in: available), display: true)
        placing = false
    }
    func windowDidResize(_ notification: Notification) { rememberFrame(resized: true) }
    func windowDidMove(_ notification: Notification) { rememberFrame() }
    private func rememberFrame(resized: Bool = false) {
        guard !placing, panel.isVisible else { return }
        let frame = panel.frame
        if resized {
            manualHeightLimit = frame.height
            defaults?.set(frame.height, forKey: "translateWindowHeightLimit")
        }
        defaults?.set([frame.minX, frame.minY, frame.width, frame.height], forKey: "translateWindowFrame")
    }
    isolated deinit { watch?.cancel(); if let monitor { NSEvent.removeMonitor(monitor) } }
}
