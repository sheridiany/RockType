import AppKit

/// Shared production surface for the native panel, DEBUG Gallery and offscreen checks.
@MainActor final class RoarkTVoiceHUDContent: NSView {
    let waveform = RoarkTVoiceHUDWaveform()
    let close = NSButton()
    let copyButton = NSButton(title: "复制文字", target: nil, action: nil)
    let heading = NSTextField(wrappingLabelWithString: "")
    let detailText = NSTextField(wrappingLabelWithString: "")
    private let scroll = NSScrollView()
    private var tracking: NSTrackingArea?
    private var hovered = false
    private var state: RoarkTVoiceHUD.State = .preparing
    private var running = false
    private var start = ProcessInfo.processInfo.systemUptime
    // Only touched on the main run loop, except invalidation during destruction.
    nonisolated(unsafe) private var timer: Timer?
    nonisolated(unsafe) private var observer: NSObjectProtocol?
    private let notifications = NSWorkspace.shared.notificationCenter
    private let reduceMotion: () -> Bool
    var onCancel: () -> Void = {}
    var onCopy: () -> Void = {}
    var onMotionChange: () -> Void = {}
    var motionEnabled: Bool { !reduceMotion() }
    var isAnimating: Bool { timer != nil }

    init(reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.reduceMotion = reduceMotion
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        for view in [waveform, close, heading, scroll, copyButton] { addSubview(view) }
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "取消语音输入")
        close.image?.isTemplate = true; close.imagePosition = .imageOnly
        close.isBordered = false; close.contentTintColor = NSColor.white.withAlphaComponent(0.7)
        close.target = self; close.action = #selector(cancel)
        close.toolTip = "取消 · Esc"
        heading.font = .systemFont(ofSize: 13, weight: .semibold); heading.textColor = .white
        heading.maximumNumberOfLines = 2
        detailText.font = .systemFont(ofSize: 13); detailText.textColor = NSColor.white.withAlphaComponent(0.85)
        detailText.maximumNumberOfLines = 0
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = detailText
        copyButton.isBordered = false; copyButton.font = .systemFont(ofSize: 12, weight: .medium)
        copyButton.contentTintColor = .white; copyButton.target = self; copyButton.action = #selector(copyText)
        waveform.setAccessibilityElement(true)
        render(.preparing)
    }
    required init?(coder: NSCoder) { nil }
    deinit { timer?.invalidate(); if let observer { notifications.removeObserver(observer) } }

    func render(_ state: RoarkTVoiceHUD.State) {
        if self.state != state { waveform.reset(); waveform.phase = 0; start = ProcessInfo.processInfo.systemUptime }
        self.state = state
        waveform.mode = state.waveformMode
        waveform.isHidden = state.isCard
        heading.isHidden = !state.isCard; scroll.isHidden = !state.isCard; copyButton.isHidden = !state.isCard
        heading.stringValue = state.isCard ? state.title : ""
        detailText.stringValue = state.detail ?? ""
        copyButton.title = state.isResult ? "复制文字" : "复制提示"
        close.setAccessibilityLabel(state.isCard ? "关闭语音提示" : "取消语音输入")
        waveform.setAccessibilityRole(state == .recording ? .levelIndicator : .progressIndicator)
        waveform.setAccessibilityLabel(state.title)
        setAccessibilityLabel("RockType 语音输入，" + state.title)
        refreshMotion(); needsLayout = true; layoutSubtreeIfNeeded()
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize); needsLayout = true
    }
    override func layout() {
        super.layout()
        layer?.backgroundColor = NSColor(calibratedWhite: 0.085, alpha: 0.96).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        layer?.borderWidth = 0.5; layer?.cornerRadius = state.isCard ? 16 : bounds.height / 2
        waveform.frame = NSRect(x: bounds.midX - 32, y: bounds.midY - 10, width: 64, height: 20)
        close.frame = NSRect(x: bounds.width - 23, y: bounds.height - 24, width: 18, height: 18)
        close.alphaValue = state.isCard || (hovered && !state.isSuccess && state != .noSpeech) ? 1 : 0
        let width = max(1, bounds.width - 32)
        heading.preferredMaxLayoutWidth = width - 16
        heading.frame = NSRect(x: 16, y: bounds.height - 49, width: width - 16, height: 34)
        scroll.frame = NSRect(x: 16, y: 47, width: width, height: max(0, bounds.height - 103))
        detailText.preferredMaxLayoutWidth = max(1, width - 12)
        detailText.frame = NSRect(x: 0, y: 0, width: max(1, width - 12), height: max(scroll.bounds.height, detailText.fittingSize.height))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: detailText.isFlipped ? 0 : max(0, detailText.frame.height - scroll.bounds.height)))
        copyButton.frame = NSRect(x: 12, y: 12, width: 78, height: 24)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsLayout = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsLayout = true }

    func setRunning(_ value: Bool) {
        running = value
        if value, observer == nil {
            observer = notifications.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshMotion(); self?.onMotionChange() }
                }
        } else if !value, let observer { notifications.removeObserver(observer); self.observer = nil }
        refreshMotion()
    }
    func refreshMotion() {
        waveform.reducedMotion = reduceMotion()
        if !motionEnabled { layer?.removeAllAnimations() }
        let moving = running && motionEnabled && !state.isCard && state != .noSpeech && !state.isSuccess
        if moving, timer == nil {
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.waveform.phase = ProcessInfo.processInfo.systemUptime - self.start
                }
            }
            RunLoop.main.add(timer, forMode: .common); self.timer = timer
        } else if !moving { timer?.invalidate(); timer = nil }
    }
    @objc private func cancel() { onCancel() }
    @objc private func copyText() { onCopy() }
}
