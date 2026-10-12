import AppKit

/// The annotation surface is invalidated only by edits; changing the crop only updates its layer mask.
@MainActor final class CaptureAnnotationView: NSView {
    let image: CGImage
    var items: [ScreenshotAnnotation] = []
    var selectedBounds: CGRect?
    var hoveredIndices: Set<Int> = []
    var restoredIndices: Set<Int> = []
    var restorationOpacity: CGFloat = 1
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    init(frame: CGRect, image: CGImage) { self.image = image; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        for (index, item) in items.enumerated() {
            let opacity: CGFloat = (hoveredIndices.contains(index) ? 0.35 : 1) * (restoredIndices.contains(index) ? restorationOpacity : 1)
            ScreenshotCompositor.draw(item, image: image, size: bounds.size, context: context, opacity: opacity)
            if hoveredIndices.contains(index) {
                context.saveGState(); context.setStrokeColor(NSColor.systemRed.cgColor)
                context.setLineWidth(1); context.setLineDash(phase: 0, lengths: [3, 3])
                context.stroke(item.bounds.insetBy(dx: -3, dy: -3)); context.restoreGState()
            }
        }
        if let selectedBounds {
            context.setStrokeColor(NSColor.controlAccentColor.cgColor); context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [4, 3]); context.stroke(selectedBounds)
            context.setLineDash(phase: 0, lengths: [])
            for handle in ScreenshotHandle.allCases {
                let p = handle.point(in: selectedBounds)
                let rect = CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)
                context.setFillColor(NSColor.white.cgColor); context.fill(rect); context.stroke(rect)
            }
        }
    }
}
