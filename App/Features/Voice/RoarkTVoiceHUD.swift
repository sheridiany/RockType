import AppKit

@MainActor
final class RoarkTVoiceHUD: NSObject {
    enum State: Equatable {
        case preparing, recording, processing
        case success(String)
        case notice(title: String, detail: String)
        case result(String, reason: String = "当前输入框未能接收文字，结果已保留。")

        var title: String {
            switch self {
            case .preparing: "模型准备中"
            case .recording: "正在录音"
            case .processing: "正在识别"
            case .success(let text): text
            case .notice(let title, _): title
            case .result: "未能填入"
            }
        }
        var detail: String? {
            switch self {
            case .notice(_, let detail): detail
            case .result(let text, let reason): reason + "\n\n" + text
            default: nil
            }
        }
        var isResult: Bool { if case .result = self { true } else { false } }
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    var onCopy: (() -> Void)?
    var onCancel: (() -> Void)?
    private let panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 188, height: 36),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let background = NSView()
    private let label = NSTextField(labelWithString: "")
    private let icon = NSTextField(labelWithString: "")
    private let clock = NSTextField(labelWithString: "0:00")
    private let waveform = RoarkTVoiceHUDWaveform()
    private let close = NSButton()
    private let detailButton = NSButton()
    private let copyButton = NSButton()
    private let scroll = NSScrollView()
    private let detailText = NSTextField(wrappingLabelWithString: "")
    private var dismissal: Task<Void, Never>?
    private var anchor: NSRect?
    private let present: (NSPanel) -> Void
    private(set) var state: State = .preparing
    private(set) var expanded = false
    var presentationSize: NSSize { panel.frame.size }
    var acceptsKeyboardFocus: Bool { panel.canBecomeKey || panel.canBecomeMain }

    init(present: @escaping (NSPanel) -> Void = { $0.orderFrontRegardless() }) {
        self.present = present
        super.init()
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor(srgbRed: 0.149, green: 0.157, blue: 0.145, alpha: 1).cgColor
        background.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        background.layer?.borderWidth = 0.5
        background.layer?.cornerRadius = 11
        panel.contentView = background
        for field in [label, icon, clock] {
            field.font = .systemFont(ofSize: 12, weight: .regular)
            field.textColor = NSColor(white: 0.93, alpha: 1)
            field.alignment = .center
            field.lineBreakMode = .byTruncatingTail
            background.addSubview(field)
        }
        clock.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        clock.textColor = NSColor(white: 0.77, alpha: 1)
        configure(close, title: "×", action: #selector(cancel))
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "取消")?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .medium))
        close.imagePosition = .imageOnly
        close.setAccessibilityLabel("取消语音输入")
        close.toolTip = "取消 · Esc"
        configure(detailButton, title: "详情", action: #selector(toggleDetails))
        configure(copyButton, title: "复制文字", action: #selector(copyResult))
        background.addSubview(waveform)
        waveform.setAccessibilityElement(true)
        waveform.setAccessibilityRole(.levelIndicator)
        panel.setAccessibilityTitle("RockType 语音输入")
        detailText.font = .systemFont(ofSize: 12)
        detailText.textColor = NSColor(white: 0.9, alpha: 1)
        detailText.maximumNumberOfLines = 0
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = detailText
        background.addSubview(scroll)
        render(.preparing)
    }

    private func configure(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.target = self
        button.action = action
        button.isBordered = false
        button.font = .systemFont(ofSize: 11)
        button.contentTintColor = NSColor(white: 0.8, alpha: 1)
        background.addSubview(button)
    }

    func show(_ state: State, dismissAfter: TimeInterval? = nil) {
        dismissal?.cancel()
        if !panel.isVisible || state == .recording {
            anchor = (NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
                ?? NSScreen.main)?.visibleFrame
        }
        render(state)
        present(panel)
        if let dismissAfter {
            dismissal = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(dismissAfter)) } catch { return }
                self?.hide()
            }
        }
    }

    func render(_ state: State) {
        self.state = state
        expanded = false
        waveform.reset()
        clock.stringValue = "0:00"
        layout()
    }

    func updateRecording(elapsed: TimeInterval, decibels: Float) {
        guard state == .recording else { return }
        let seconds = Int(max(0, min(elapsed.isFinite ? elapsed : 0, 3_600)))
        clock.stringValue = String(format: "%d:%02d", seconds / 60, seconds % 60)
        waveform.append(decibels: decibels)
    }

    private func layout() {
        let hasDetail = state.detail != nil
        let width: CGFloat = expanded ? 288 : (hasDetail ? 240 : 188)
        let height: CGFloat = expanded ? 180 : 36
        panel.setContentSize(NSSize(width: width, height: height))
        background.frame = NSRect(x: 0, y: 0, width: width, height: height)
        if let anchor {
            panel.setFrameOrigin(NSPoint(x: anchor.midX - width / 2, y: anchor.minY + 18))
        }
        let recording = state == .recording
        label.isHidden = recording
        waveform.isHidden = !recording
        clock.isHidden = !recording
        label.stringValue = state.title
        label.toolTip = state.title
        label.frame = NSRect(x: 29, y: 10, width: width - (hasDetail ? 109 : 64), height: 17)
        icon.frame = NSRect(x: 9, y: 10, width: 14, height: 17)
        icon.stringValue = recording ? "•" : (hasDetail ? "!" : "·")
        if state.isResult { icon.stringValue = "↗" }
        if case .success = state { icon.stringValue = "✓" }
        icon.textColor = recording ? NSColor(srgbRed: 0.93, green: 0.55, blue: 0.49, alpha: 1)
            : NSColor(white: 0.78, alpha: 1)
        waveform.frame = NSRect(x: 29, y: 9, width: 72, height: 18)
        waveform.setAccessibilityLabel("录音音量；松开 Fn 结束，Esc 取消")
        // NSTextField's 11 pt digit ink sits above its frame center. Align the visible
        // digits (not the line box) with the waveform; covered by a rendered-pixel test.
        clock.frame = NSRect(x: 107, y: 8, width: 42, height: 17)
        close.frame = NSRect(x: width - 31, y: 6, width: 24, height: 24)
        detailButton.isHidden = !hasDetail
        detailButton.title = expanded ? "收起" : (state.isResult ? "展开" : "详情")
        detailButton.frame = NSRect(x: width - 77, y: 6, width: 40, height: 24)
        scroll.isHidden = !expanded
        copyButton.isHidden = !expanded || !state.isResult
        scroll.frame = NSRect(x: 14, y: state.isResult ? 70 : 46, width: width - 28,
                              height: state.isResult ? 96 : 120)
        detailText.stringValue = state.detail ?? ""
        detailText.preferredMaxLayoutWidth = width - 44
        let textHeight = max(scroll.frame.height, detailText.fittingSize.height)
        detailText.frame = NSRect(x: 0, y: 0, width: width - 44, height: textHeight)
        let top = detailText.isFlipped ? 0 : max(0, textHeight - scroll.frame.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: top))
        copyButton.frame = NSRect(x: 14, y: 41, width: 68, height: 24)
    }

    @objc func toggleDetails() {
        guard state.detail != nil else { return }
        dismissal?.cancel()
        expanded.toggle()
        layout()
    }

    func hide() { dismissal?.cancel(); dismissal = nil; panel.orderOut(nil); anchor = nil }
    @objc private func copyResult() { onCopy?() }
    @objc private func cancel() { onCancel?(); hide() }
}
