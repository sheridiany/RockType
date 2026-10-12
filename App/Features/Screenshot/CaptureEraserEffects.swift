import AppKit
import QuartzCore

/// All transient feedback lives here, outside ScreenshotCompositor's export input.
@MainActor final class CaptureEraserEffects: NSView {
    struct Trail { let sweep: ScreenshotEraser.Sweep; let start: CFTimeInterval }
    struct Ghost {
        let annotation: ScreenshotAnnotation
        let origin: CGPoint
        let direction: CGVector
        let start: CFTimeInterval
    }
    let image: CGImage
    var selection = CGRect.zero
    var center: CGPoint? { didSet { needsDisplay = true } }
    var diameter: CGFloat = 24 { didSet { needsDisplay = true } }
    var reducedMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var onFrame: (CGFloat) -> Void = { _ in }
    private(set) var trails: [Trail] = []
    private(set) var ghosts: [Ghost] = []
    private(set) var restorationStart: CFTimeInterval?
    private var link: CADisplayLink?
    var frameTime: CFTimeInterval? // Deterministic offscreen frames use the very same drawing path.
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    init(frame: CGRect, image: CGImage) { self.image = image; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func trail(_ sweep: ScreenshotEraser.Sweep, at time: CFTimeInterval = CACurrentMediaTime()) {
        guard !reducedMotion() else { return }
        trails.removeAll { time - $0.start >= 0.2 }
        trails.append(Trail(sweep: sweep, start: time))
        if trails.count > 128 { trails.removeFirst(trails.count - 128) }
        animate()
    }
    func removed(_ items: [ScreenshotAnnotation], sweep: ScreenshotEraser.Sweep, at time: CFTimeInterval = CACurrentMediaTime()) {
        ghosts.removeAll { time - $0.start >= 0.18 }
        let dx = sweep.to.x - sweep.from.x, dy = sweep.to.y - sweep.from.y, length = hypot(dx, dy)
        let direction = length > 0 ? CGVector(dx: dx / length, dy: dy / length) : CGVector(dx: 0.8, dy: -0.6)
        ghosts += items.map {
            let box = $0.bounds
            let origin = CGPoint(x: min(box.maxX, max(box.minX, sweep.to.x)), y: min(box.maxY, max(box.minY, sweep.to.y)))
            return Ghost(annotation: $0, origin: origin, direction: direction, start: time)
        }
        // Feedback is bounded even when a single sweep removes a large stack.
        if ghosts.count > 24 { ghosts.removeFirst(ghosts.count - 24) }
        if !items.isEmpty { animate() }
    }
    func restore(at time: CFTimeInterval = CACurrentMediaTime()) {
        trails.removeAll(); ghosts.removeAll(); restorationStart = time; animate()
    }
    func clear() {
        link?.invalidate(); link = nil
        trails.removeAll(); ghosts.removeAll(); restorationStart = nil; center = nil
        onFrame(1); needsDisplay = true
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { clear() } }
    private func animate() {
        needsDisplay = true
        guard window != nil, link == nil else { return }
        link = displayLink(target: self, selector: #selector(tick(_:)))
        link?.add(to: .main, forMode: .common)
    }
    @objc private func tick(_ link: CADisplayLink) { advance(to: CACurrentMediaTime()) }
    func advance(to time: CFTimeInterval) {
        trails.removeAll { time - $0.start >= 0.2 }; ghosts.removeAll { time - $0.start >= 0.18 }
        if reducedMotion() { trails.removeAll() }
        if let start = restorationStart {
            onFrame(min(1, max(0, (time - start) / 0.15)))
            if time - start >= 0.15 { restorationStart = nil }
        }
        needsDisplay = true
        if trails.isEmpty && ghosts.isEmpty && restorationStart == nil { link?.invalidate(); link = nil }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        let time = frameTime ?? CACurrentMediaTime(), reduced = reducedMotion()
        c.saveGState(); c.clip(to: selection)
        if !reduced {
            for trail in trails {
                let progress = max(0, min(1, (time - trail.start) / 0.2))
                c.setStrokeColor(NSColor.white.withAlphaComponent(0.2 * (1 - progress)).cgColor)
                c.setLineWidth(trail.sweep.radius * 2); c.setLineCap(.round)
                c.move(to: trail.sweep.from); c.addLine(to: trail.sweep.to); c.strokePath()
            }
        }
        for ghost in ghosts {
            let progress = max(0, min(1, (time - ghost.start) / 0.18))
            guard progress < 1 else { continue }
            let ease = 1 - pow(1 - progress, 3), scale = reduced ? 1 : 1 - 0.08 * ease
            let rect = ghost.annotation.bounds
            c.saveGState(); c.translateBy(x: rect.midX, y: rect.midY); c.scaleBy(x: scale, y: scale)
            c.translateBy(x: -rect.midX, y: -rect.midY)
            ScreenshotCompositor.draw(ghost.annotation, image: image, size: bounds.size, context: c, opacity: 0.35 * (1 - progress))
            c.restoreGState()
            if !reduced {
                for index in 0..<6 {
                    let spread = CGFloat(index) - 2.5, distance = (9 + CGFloat(index % 3) * 4) * ease
                    let x = ghost.origin.x + ghost.direction.dx * distance - ghost.direction.dy * spread * ease * 2
                    let y = ghost.origin.y + ghost.direction.dy * distance + ghost.direction.dx * spread * ease * 2 + 4 * progress * progress
                    let size = (1.5 + CGFloat(index % 2)) * (1 - progress * 0.6)
                    c.setFillColor(ghost.annotation.color.withAlphaComponent(0.65 * (1 - progress)).cgColor)
                    c.fillEllipse(in: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size))
                }
            }
        }
        c.restoreGState()
        if let center {
            let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
            c.setLineWidth(3); c.setStrokeColor(NSColor.black.withAlphaComponent(0.75).cgColor); c.strokeEllipse(in: rect.insetBy(dx: -1, dy: -1))
            c.setLineWidth(1); c.setStrokeColor(NSColor.white.cgColor); c.strokeEllipse(in: rect)
        }
    }
}
