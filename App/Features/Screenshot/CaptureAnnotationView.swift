import AppKit

/// The annotation surface is invalidated only by edits; changing the crop only updates its layer mask.
@MainActor final class CaptureAnnotationView: NSView {
    let image: CGImage
    var items: [ScreenshotAnnotation] = []
    var selectedBounds: CGRect?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    init(frame: CGRect, image: CGImage) { self.image = image; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(dirtyRect)
        for item in items { ScreenshotCompositor.draw(item, image: image, size: bounds.size, context: context) }
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
