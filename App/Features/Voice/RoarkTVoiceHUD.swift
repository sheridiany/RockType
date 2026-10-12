import AppKit
import QuartzCore

@MainActor final class RoarkTVoiceHUD: NSObject {
    enum State: Equatable {
        case preparing, recording, processing, polishing, noSpeech
        case success(String)
        case notice(title: String, detail: String)
        case result(String, reason: String = "当前输入框未能接收文字，结果已保留。")
        var title: String {
            switch self {
            case .preparing: "正在准备语音"
            case .recording: "正在录音；松开 Fn 结束，Esc 取消；最长三分钟"
            case .processing: "正在识别"
            case .polishing: "正在润色"
            case .noSpeech: "未检测到有效声音"
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
        var isCard: Bool { detail != nil }
        var isResult: Bool { if case .result = self { true } else { false } }
        var isSuccess: Bool { if case .success = self { true } else { false } }
        var size: NSSize {
            if isCard { return NSSize(width: 320, height: 196) }
            switch self {
            case .processing, .polishing: return NSSize(width: 80, height: 32)
            case .success, .noSpeech: return NSSize(width: 64, height: 32)
            default: return NSSize(width: 112, height: 32)
            }
        }
        var waveformMode: RoarkTVoiceHUDWaveform.Mode {
            switch self {
            case .recording: .recording
            case .processing: .processing
            case .polishing: .polishing
            case .success: .success
            case .noSpeech: .noSpeech
            default: .preparing
            }
        }
    }
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
    private let panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 112, height: 32),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let content: RoarkTVoiceHUDContent
    var onCopy: (() -> Void)?
    var onCancel: (() -> Void)?
    private let present: (NSPanel) -> Void
    private let visibleFrame: () -> NSRect
    private var dismissal: Task<Void, Never>?
    private var exitTask: Task<Void, Never>?
    private var generation = UUID()
    private var shown = false
    private var screenFrame: NSRect?
    private(set) var state: State = .preparing
    var presentationSize: NSSize { panel.frame.size }
    var acceptsKeyboardFocus: Bool { panel.canBecomeKey || panel.canBecomeMain }
    var isPresented: Bool { shown }

    init(present: @escaping (NSPanel) -> Void = { $0.orderFrontRegardless() },
         reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
         visibleFrame: @escaping () -> NSRect = {
             (NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main)?.visibleFrame ?? .zero
         }) {
        self.present = present; self.visibleFrame = visibleFrame
        content = RoarkTVoiceHUDContent(reduceMotion: reduceMotion)
        super.init()
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = content
        panel.setAccessibilityTitle("RockType 语音输入")
        content.onCancel = { [weak self] in
            self?.onCancel?()
            if self?.shown == true { self?.hide() }
        }
        content.onCopy = { [weak self] in self?.onCopy?() }
        content.onMotionChange = { [weak self] in
            guard let self, !content.motionEnabled else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().setFrame(Self.frame(for: state.size, visibleFrame: visibleFrame()), display: true)
            }
        }
        render(.preparing)
    }
    static func frame(for size: NSSize, visibleFrame: NSRect) -> NSRect {
        NSRect(x: visibleFrame.midX - size.width / 2, y: visibleFrame.minY + 16, width: size.width, height: size.height)
    }
    /// Immediate rendering is also used by offscreen tests. Presentation owns animation/lifetime.
    func render(_ state: State) {
        self.state = state; panel.setContentSize(state.size)
        content.render(state)
    }
    func show(_ state: State, dismissAfter: TimeInterval? = nil) {
        let changed = self.state != state
        if !changed && shown { return }
        generation = UUID(); let id = generation
        dismissal?.cancel(); exitTask?.cancel(); exitTask = nil
        let entering = !shown; shown = true
        let previous = panel.frame
        render(state)
        if entering { content.waveform.reset() }
        let screen = visibleFrame(); screenFrame = screen
        let target = Self.frame(for: state.size, visibleFrame: screen)
        if entering { content.layer?.removeAllAnimations() }
        else { content.layer?.removeAnimation(forKey: "noSpeech") }
        panel.alphaValue = 1
        if content.motionEnabled {
            panel.setFrame(entering ? target.offsetBy(dx: 0, dy: -7) : previous, display: false)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = entering ? 0.25 : 0.2
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
                panel.animator().setFrame(target, display: true)
            }
            if entering {
                let spring = CASpringAnimation(keyPath: "transform.scale")
                spring.fromValue = 0.9; spring.toValue = 1; spring.mass = 1
                spring.stiffness = 320; spring.damping = 24; spring.duration = 0.25
                content.layer?.add(spring, forKey: "entrance")
                let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.15
                content.layer?.add(fade, forKey: "entranceOpacity")
            }
            if state == .noSpeech {
                let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
                shake.values = [0, -3, 3, -2, 2, 0]; shake.duration = 0.24
                content.layer?.add(shake, forKey: "noSpeech")
            }
        } else { panel.setFrame(target, display: false) }
        content.setRunning(true); present(panel)
        if let delay = dismissAfter ?? (state.isSuccess ? 0.65 : state == .noSpeech ? 0.7 : nil) {
            let deadline = ContinuousClock.now.advanced(by: .seconds(delay))
            dismissal = Task { [weak self] in
                do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
                guard let self, generation == id else { return }
                hide()
            }
        }
    }
    func updateRecording(decibels: Float) {
        guard state == .recording else { return }
        content.waveform.append(decibels: decibels)
        // Track the current active screen, using its Dock-excluding visible frame.
        let screen = visibleFrame()
        if shown, screenFrame != screen {
            screenFrame = screen
            panel.setFrameOrigin(Self.frame(for: state.size, visibleFrame: screen).origin)
        }
    }
    func hide() {
        generation = UUID(); let id = generation
        dismissal?.cancel(); dismissal = nil; exitTask?.cancel(); exitTask = nil
        let animate = shown && content.motionEnabled && !state.isCard
        shown = false; content.setRunning(false)
        state = .preparing
        // Cards disappear immediately; normal states keep their final shape through the fade.
        guard animate else {
            content.render(.preparing); panel.orderOut(nil); panel.alphaValue = 1; return
        }
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1; shrink.toValue = 0.94; shrink.duration = 0.14
        content.layer?.add(shrink, forKey: "exit")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.14
        fade.fillMode = .forwards; fade.isRemovedOnCompletion = false
        content.layer?.add(fade, forKey: "exitOpacity")
        exitTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self, generation == id else { return }
            panel.orderOut(nil); content.render(.preparing); panel.alphaValue = 1; exitTask = nil
        }
    }
}
