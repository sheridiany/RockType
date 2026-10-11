import AppKit
import RoarkTPlatform

/// Point-size geometry, independent of the image's pixel resolution.
enum PinnedImageGeometry {
    static func scale(_ proposed: CGFloat) -> CGFloat {
        guard proposed.isFinite else { return 1 }
        return min(4, max(0.1, proposed))
    }

    static func fitted(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        guard rect.width > 0, rect.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let factor = min(1, bounds.width / rect.width, bounds.height / rect.height)
        let size = CGSize(width: rect.width * factor, height: rect.height * factor)
        return CGRect(x: min(max(rect.minX, bounds.minX), bounds.maxX - size.width),
                      y: min(max(rect.minY, bounds.minY), bounds.maxY - size.height),
                      width: size.width, height: size.height)
    }

    static func zoom(_ frame: CGRect, base: CGSize, scale: CGFloat, in bounds: CGRect) -> CGRect {
        let size = CGSize(width: base.width * self.scale(scale), height: base.height * self.scale(scale))
        return fitted(CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                             width: size.width, height: size.height), in: bounds)
    }
}

/// Retains multiple independent panels until dismissed. Never writes images to disk.
@MainActor final class PinnedImageController: NSObject, NSWindowDelegate {
    static let shared = PinnedImageController()
    private(set) var panels: [NSPanel] = []
    private let allowed: () -> Bool
    private let copyImage: (CGImage) throws -> Void
    private var protectionTask: Task<Void, Never>?

    init(allowed: @escaping () -> Bool = { SecureInput.status() == .allowed },
         copyImage: @escaping (CGImage) throws -> Void = { try ScreenshotOutput.shared.copyImage($0) }) {
        self.allowed = allowed; self.copyImage = copyImage
    }

    /// `rect` is the selection's global AppKit screen rect in points (bottom-left origin).
    /// Pass the final composited image, including annotations. Returns false if protected.
    @discardableResult func pin(_ image: CGImage, at rect: CGRect) -> Bool {
        guard allowed(), rect.width.isFinite, rect.height.isFinite,
              rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width > 0, rect.height > 0,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }) ?? NSScreen.main else { return false }
        let frame = PinnedImageGeometry.fitted(rect, in: screen.visibleFrame)
        let panel = PinnedImagePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.delegate = self
        let view = PinnedImageView(image: image, baseSize: frame.size, allowed: allowed, copyImage: copyImage)
        panel.contentView = view
        panels.append(panel)
        panel.orderFrontRegardless()
        panel.makeKey(); panel.makeFirstResponder(view)
        startProtection()
        return true
    }

    func closeAll() {
        for panel in panels { panel.close() }
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        panel.contentView = nil
        panels.removeAll { $0 === panel }
        if panels.isEmpty { protectionTask?.cancel(); protectionTask = nil }
    }

    private func startProtection() {
        guard protectionTask == nil else { return }
        protectionTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self else { return }
                if !self.allowed() { self.closeAll(); return }
            }
        }
    }
}

private final class PinnedImagePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor private final class PinnedImageView: NSView {
    private let image: CGImage
    private let baseSize: CGSize
    private let allowed: () -> Bool
    private let copyImage: (CGImage) throws -> Void
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(image: CGImage, baseSize: CGSize, allowed: @escaping () -> Bool,
         copyImage: @escaping (CGImage) throws -> Void) {
        self.image = image; self.baseSize = baseSize; self.allowed = allowed; self.copyImage = copyImage
        super.init(frame: CGRect(origin: .zero, size: baseSize))
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resizeAspect
        toolTip = "拖动移动 · 滚轮或双指缩放 · ⌘C 复制 · 双击或 Esc 关闭"
        setAccessibilityLabel("贴图")
        setAccessibilityHelp(toolTip)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        guard allowed() else { window?.close(); return }
        if event.clickCount == 2 { window?.close(); return }
        window?.makeKey(); window?.makeFirstResponder(self)
        window?.performDrag(with: event)
    }
    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.005 : 0.05)
        resize(by: exp(min(1, max(-1, delta))))
    }
    override func magnify(with event: NSEvent) { resize(by: 1 + event.magnification) }
    private func resize(by factor: CGFloat) {
        guard allowed() else { window?.close(); return }
        guard let window, let screen = window.screen else { return }
        let scale = window.frame.width / baseSize.width * factor
        window.setFrame(PinnedImageGeometry.zoom(window.frame, base: baseSize, scale: scale,
                                                in: screen.visibleFrame), display: true)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { window?.close(); return }
        if !performKeyEquivalent(with: event) { super.keyDown(with: event) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.charactersIgnoringModifiers?.lowercased() == "c" else { return false }
        guard allowed() else { window?.close(); return true }
        do { try copyImage(image) } catch { NSSound.beep() }
        return true
    }
}
