import AppKit

struct CapturePixelSample {
    let pixel: CGPoint
    let patch: CGImage
    let targetInPatch: CGPoint
    let hex: String
}

/// Reads at most 15 × 15 source pixels; no full-screen decode buffer or screen capture per move.
enum CapturePixelSampler {
    static func sample(image: CGImage, point: CGPoint, size: CGSize) -> CapturePixelSample? {
        guard size.width > 0, size.height > 0, point.x.isFinite, point.y.isFinite,
              point.x >= 0, point.y >= 0, point.x < size.width, point.y < size.height else { return nil }
        let x = min(image.width - 1, Int(floor(point.x * CGFloat(image.width) / size.width)))
        let y = min(image.height - 1, Int(floor(point.y * CGFloat(image.height) / size.height)))
        let rect = CGRect(x: max(0, x - 7), y: max(0, y - 7), width: min(15, image.width), height: min(15, image.height))
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let patch = image.cropping(to: rect), let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let alpha = Int(bytes[3])
        let channels = (0..<3).map { alpha == 0 ? 0 : min(255, Int(bytes[$0]) * 255 / alpha) }
        return CapturePixelSample(pixel: CGPoint(x: x, y: y), patch: patch,
            targetInPatch: CGPoint(x: x - Int(rect.minX), y: y - Int(rect.minY)),
            hex: String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2]))
    }
    static func frame(near point: CGPoint, bounds: CGRect, avoiding obstacle: CGRect? = nil) -> CGRect {
        let size = CGSize(width: min(142, bounds.width), height: min(170, bounds.height))
        let right = point.x + 24, left = point.x - size.width - 24
        let below = point.y + 24, above = point.y - size.height - 24
        let xs = right + size.width <= bounds.maxX ? [right, left] : [left, right]
        let ys = below + size.height <= bounds.maxY ? [below, above] : [above, below]
        let candidates = ys.flatMap { y in xs.map { x in
            CGRect(x: max(bounds.minX, min(x, bounds.maxX - size.width)),
                   y: max(bounds.minY, min(y, bounds.maxY - size.height)), width: size.width, height: size.height)
        } }
        guard let obstacle else { return candidates[0] }
        return candidates.first { !$0.intersects(obstacle) } ?? candidates[0]
    }

}

/// A small independent view: moving the pointer never invalidates the frozen image or annotation surface.
@MainActor final class CaptureMagnifier: NSView {
    var sample: CapturePixelSample? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let sample, let c = NSGraphicsContext.current?.cgContext else { return }
        c.clear(dirtyRect)
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        NSColor(white: 0.12, alpha: 0.97).setFill(); background.fill()
        NSColor.white.withAlphaComponent(0.4).setStroke(); background.lineWidth = 1; background.stroke()
        let lens = CGRect(x: 8, y: 8, width: bounds.width - 16, height: bounds.width - 16)
        let scale: CGFloat = 8
        let target = CGPoint(x: lens.midX - scale / 2, y: lens.midY - scale / 2)
        let patchRect = CGRect(x: target.x - sample.targetInPatch.x * scale,
                              y: target.y - sample.targetInPatch.y * scale,
                              width: CGFloat(sample.patch.width) * scale, height: CGFloat(sample.patch.height) * scale)
        c.saveGState(); c.clip(to: lens)
        c.setFillColor(NSColor(white: 0.25, alpha: 1).cgColor); c.fill(lens)
        c.interpolationQuality = .none
        c.translateBy(x: patchRect.minX, y: patchRect.maxY); c.scaleBy(x: 1, y: -1)
        c.draw(sample.patch, in: CGRect(origin: .zero, size: patchRect.size)); c.restoreGState()
        let focus = CGRect(origin: target, size: CGSize(width: scale, height: scale))
        c.setStrokeColor(NSColor.black.cgColor); c.setLineWidth(3); c.stroke(focus)
        c.setStrokeColor(NSColor.white.cgColor); c.setLineWidth(1); c.stroke(focus)
        let label = sample.hex + "  C 复制"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white]
        (label as NSString).draw(at: CGPoint(x: 10, y: lens.maxY + 10), withAttributes: attrs)
    }
}
