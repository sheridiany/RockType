import AppKit
import SwiftUI

struct ScreenshotAnnotation {
    var tool: ScreenshotEditorModel.Tool
    var points: [CGPoint]
    var text = ""
    var number = 1
    var color: NSColor = NSColor(Tokens.palette(.light).danger)
    var width: CGFloat = Tokens.Size.focusRing
    var rect: CGRect {
        guard let first = points.first, let last = points.last else { return .zero }
        return CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                      width: abs(last.x - first.x), height: abs(last.y - first.y))
    }
}
struct ScreenshotAnnotationHistory {
    private(set) var items: [ScreenshotAnnotation] = []
    private(set) var undone: [ScreenshotAnnotation] = []
    mutating func append(_ item: ScreenshotAnnotation) { items.append(item); undone.removeAll() }
    mutating func undo() { if let last = items.popLast() { undone.append(last) } }
    mutating func redo() { if let last = undone.popLast() { items.append(last) } }
}

enum ScreenshotCompositor {
    /// Crop and render in original pixels. No NSImage focus lock (which would use display scale).
    static func render(image: CGImage, size: CGSize, selection: CGRect,
                       annotations: [ScreenshotAnnotation]) -> CGImage? {
        let crop = CaptureGeometry.pixels(selection, image: image, size: size)
        guard !crop.isEmpty, let source = image.cropping(to: crop),
              let ctx = CGContext(data: nil, width: source.width, height: source.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        ctx.translateBy(x: 0, y: CGFloat(source.height)); ctx.scaleBy(x: 1, y: -1)
        let sx = CGFloat(image.width) / size.width, sy = CGFloat(image.height) / size.height
        ctx.scaleBy(x: sx, y: sy); ctx.translateBy(x: -crop.minX / sx, y: -crop.minY / sy)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }
        for annotation in annotations { draw(annotation, image: image, size: size, context: ctx) }
        return ctx.makeImage()
    }
    private static func draw(_ a: ScreenshotAnnotation, image: CGImage, size: CGSize, context c: CGContext) {
        guard let start = a.points.first, let end = a.points.last else { return }
        c.saveGState(); defer { c.restoreGState() }
        c.setStrokeColor(a.color.cgColor); c.setFillColor(a.color.cgColor)
        c.setLineWidth(a.width); c.setLineCap(.round); c.setLineJoin(.round)
        switch a.tool {
        case .rectangle: c.stroke(a.rect)
        case .ellipse: c.strokeEllipse(in: a.rect)
        case .pen:
            c.addLines(between: a.points); c.strokePath()
        case .arrow:
            c.move(to: start); c.addLine(to: end); c.strokePath()
            let angle = atan2(end.y - start.y, end.x - start.x), length = max(10, a.width * 4)
            c.move(to: end)
            c.addLine(to: CGPoint(x: end.x - length * cos(angle - .pi / 6), y: end.y - length * sin(angle - .pi / 6)))
            c.move(to: end)
            c.addLine(to: CGPoint(x: end.x - length * cos(angle + .pi / 6), y: end.y - length * sin(angle + .pi / 6)))
            c.strokePath()
        case .text:
            (a.text as NSString).draw(at: start, withAttributes: [.font: NSFont.systemFont(ofSize: max(16, a.width * 6)), .foregroundColor: a.color])
        case .number:
            let r: CGFloat = max(12, a.width * 4)
            c.fillEllipse(in: CGRect(x: start.x - r, y: start.y - r, width: r * 2, height: r * 2))
            let text = String(a.number) as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: r), .foregroundColor: NSColor.white]
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: start.x - size.width / 2, y: start.y - size.height / 2), withAttributes: attrs)
        case .mosaic:
            let pixelRect = CaptureGeometry.pixels(a.rect, image: image, size: size)
            guard !pixelRect.isEmpty, let patch = image.cropping(to: pixelRect),
                  let small = CGContext(data: nil, width: max(1, patch.width / 16), height: max(1, patch.height / 16),
                                       bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            small.interpolationQuality = .low
            small.draw(patch, in: CGRect(x: 0, y: 0, width: small.width, height: small.height))
            guard let mosaic = small.makeImage() else { return }
            let sx = CGFloat(image.width) / size.width, sy = CGFloat(image.height) / size.height
            let rect = CGRect(x: pixelRect.minX / sx, y: pixelRect.minY / sy, width: pixelRect.width / sx, height: pixelRect.height / sy)
            c.interpolationQuality = .none
            c.translateBy(x: rect.minX, y: rect.maxY); c.scaleBy(x: 1, y: -1)
            c.draw(mosaic, in: CGRect(origin: .zero, size: rect.size))
        }
    }
}
