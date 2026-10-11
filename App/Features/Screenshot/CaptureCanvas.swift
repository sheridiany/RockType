import AppKit

@MainActor final class CaptureCanvas: NSView {
    let image: CGImage
    var selection = CGRect.zero
    var onCancel: () -> Void = {}
    var onComplete: (CGImage) -> Void = { _ in }
    private var anchor = CGPoint.zero
    private var original = CGRect.zero
    private var handle: ScreenshotHandle?
    private var moving = false
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(frame: CGRect, image: CGImage) {
        self.image = image; super.init(frame: frame)
        setAccessibilityLabel("截图框选：拖动框选，手柄调整，方向键微调，Enter 完成，Escape 取消")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: image, size: bounds.size).draw(in: bounds)
        let mask = NSBezierPath(rect: bounds)
        if !selection.isEmpty { mask.appendRect(selection) }
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.48).setFill(); mask.fill()
        guard !selection.isEmpty else { return }
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: selection); border.lineWidth = Tokens.Screenshot.selectionStroke; border.stroke()
        for h in ScreenshotHandle.allCases {
            let p = h.point(in: selection)
            NSColor.white.setFill(); NSBezierPath(ovalIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)).fill()
        }
        let pixels = CaptureGeometry.pixels(selection, image: image, size: bounds.size)
        let label = "\(Int(pixels.width)) × \(Int(pixels.height)) · ↩ 完成 · Esc 取消"
        label.draw(at: CGPoint(x: max(8, min(selection.minX, bounds.width - 300)), y: max(8, selection.minY - 25)),
                   withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white,
                                    .backgroundColor: NSColor.black.withAlphaComponent(0.7)])
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey(); window?.makeFirstResponder(self)
        anchor = convert(event.locationInWindow, from: nil); original = selection
        handle = ScreenshotHandle.allCases.first { h in
            let p = h.point(in: selection)
            return !selection.isEmpty && hypot(p.x - anchor.x, p.y - anchor.y) <= 9
        }
        moving = handle == nil && selection.contains(anchor)
        if handle == nil && !moving { selection = .zero }
    }
    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let delta = CGSize(width: p.x - anchor.x, height: p.y - anchor.y)
        if let handle { selection = CaptureGeometry.resized(original, handle: handle, by: delta, bounds: bounds) }
        else if moving { selection = CaptureGeometry.moved(original, by: delta, bounds: bounds) }
        else { selection = CaptureGeometry.selection(from: anchor, to: p, bounds: bounds) }
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel(); return }
        if event.keyCode == 36, !selection.isEmpty {
            if let cropped = image.cropping(to: CaptureGeometry.pixels(selection, image: image, size: bounds.size)) { onComplete(cropped) }
            return
        }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        let delta: CGSize
        switch event.keyCode {
        case 123: delta = CGSize(width: -step, height: 0)
        case 124: delta = CGSize(width: step, height: 0)
        case 125: delta = CGSize(width: 0, height: step)
        case 126: delta = CGSize(width: 0, height: -step)
        default: super.keyDown(with: event); return
        }
        selection = CaptureGeometry.moved(selection, by: delta, bounds: bounds); needsDisplay = true
    }
}
