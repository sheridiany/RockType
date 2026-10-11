import AppKit
import SwiftUI
import RoarkTCore

enum ScreenshotTool: String, CaseIterable, Sendable {
    case rectangle, ellipse, arrow, line, pen, highlighter, mosaic, text, number, eraser
    var title: String {
        switch self {
        case .rectangle: "圆角矩形"
        case .ellipse: "椭圆"
        case .arrow: "箭头"
        case .line: "直线"
        case .pen: "画笔"
        case .highlighter: "荧光笔"
        case .mosaic: "马赛克"
        case .text: "文字"
        case .number: "序号"
        case .eraser: "删除标注"
        }
    }
    var symbol: String {
        switch self {
        case .rectangle: "rectangle.roundedtop"
        case .ellipse: "oval"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .mosaic: "square.grid.3x3.fill"
        case .text: "textformat"
        case .number: "number.circle"
        case .eraser: "eraser"
        }
    }
    var shortcut: String { self == .eraser ? "E" : "⇧\(Self.allCases.firstIndex(of: self)! + 1)" }
    static func shortcut(keyCode: UInt16) -> Self? {
        let keys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        return keys.firstIndex(of: keyCode).map { allCases[$0] }
    }
}

struct ScreenshotAnnotation: Equatable {
    var tool: ScreenshotTool
    var points: [CGPoint]
    var text = ""
    var number = 1
    var color: NSColor = NSColor(srgbRed: 216 / 255, green: 74 / 255, blue: 47 / 255, alpha: 1)
    var width: CGFloat = 5
    var fontSize: CGFloat = 17
    var textMaxWidth: CGFloat?
    var rect: CGRect {
        guard let first = points.first, let last = points.last else { return .zero }
        return CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                      width: abs(last.x - first.x), height: abs(last.y - first.y))
    }
}
struct ScreenshotAnnotationHistory {
    private(set) var items: [ScreenshotAnnotation] = []
    private var past: [[ScreenshotAnnotation]] = []
    private var future: [[ScreenshotAnnotation]] = []
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    private mutating func checkpoint() { past.append(items); future.removeAll() }
    mutating func append(_ item: ScreenshotAnnotation) {
        if item.tool == .text && ScreenshotText.isEmpty(item.text) { return }
        checkpoint(); items.append(item)
    }
    mutating func commitText(_ item: ScreenshotAnnotation, replacing index: Int?) {
        guard let index else { append(item); return }
        guard items.indices.contains(index) else { return }
        if items[index].text == item.text && items[index].textMaxWidth == item.textMaxWidth { return }
        checkpoint()
        if ScreenshotText.isEmpty(item.text) { items.remove(at: index) }
        else { items[index] = item }
    }
    mutating func replace(at index: Int, with item: ScreenshotAnnotation) {
        guard items.indices.contains(index), items[index] != item else { return }
        checkpoint(); items[index] = item
    }
    mutating func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        checkpoint(); items.remove(at: index)
    }
    mutating func undo() {
        guard let previous = past.popLast() else { return }
        future.append(items); items = previous
    }
    mutating func redo() {
        guard let next = future.popLast() else { return }
        past.append(items); items = next
    }
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
    static func draw(_ a: ScreenshotAnnotation, image: CGImage, size: CGSize, context c: CGContext) {
        guard let start = a.points.first, let end = a.points.last else { return }
        c.saveGState(); defer { c.restoreGState() }
        c.setStrokeColor(a.color.cgColor); c.setFillColor(a.color.cgColor)
        c.setLineWidth(a.width); c.setLineCap(.round); c.setLineJoin(.round)
        switch a.tool {
        case .rectangle:
            c.addPath(CGPath(roundedRect: a.rect, cornerWidth: min(8, a.rect.width / 2),
                             cornerHeight: min(8, a.rect.height / 2), transform: nil)); c.strokePath()
        case .ellipse: c.strokeEllipse(in: a.rect)
        case .pen, .highlighter, .line:
            if a.tool == .highlighter { c.setAlpha(0.3); c.setLineCap(.butt) }
            if a.points.allSatisfy({ $0 == start }) {
                c.fillEllipse(in: CGRect(x: start.x - a.width / 2, y: start.y - a.width / 2, width: a.width, height: a.width))
            } else { c.addLines(between: a.points); c.strokePath() }
        case .eraser: break
        case .arrow:
            c.move(to: start); c.addLine(to: end); c.strokePath()
            let angle = atan2(end.y - start.y, end.x - start.x), length = max(10, a.width * 4)
            c.move(to: end)
            c.addLine(to: CGPoint(x: end.x - length * cos(angle - .pi / 6), y: end.y - length * sin(angle - .pi / 6)))
            c.move(to: end)
            c.addLine(to: CGPoint(x: end.x - length * cos(angle + .pi / 6), y: end.y - length * sin(angle + .pi / 6)))
            c.strokePath()
        case .text:
            ScreenshotTextLayout(annotation: a).draw(at: start)
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
                  let small = CGContext(data: nil, width: max(1, Int(CGFloat(patch.width) / max(1, a.width * CGFloat(image.width) / size.width))),
                                       height: max(1, Int(CGFloat(patch.height) / max(1, a.width * CGFloat(image.height) / size.height))),
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

extension ScreenshotAnnotation {
    var bounds: CGRect {
        guard let first = points.first else { return .zero }
        if tool == .text { return CGRect(origin: first, size: ScreenshotTextLayout(annotation: self).size) }
        if tool == .number {
            let radius = max(12, width * 4)
            return CGRect(x: first.x - radius, y: first.y - radius, width: radius * 2, height: radius * 2)
        }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: max(1, xs.max()! - xs.min()!), height: max(1, ys.max()! - ys.min()!))
    }
    func contains(_ point: CGPoint) -> Bool {
        let tolerance = max(6, width / 2 + 3)
        guard bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { return false }
        switch tool {
        case .text, .number, .mosaic: return true
        case .rectangle:
            return !rect.insetBy(dx: tolerance, dy: tolerance).contains(point)
        case .ellipse:
            guard rect.width > 0, rect.height > 0 else { return true }
            let x = (point.x - rect.midX) / (rect.width / 2)
            let y = (point.y - rect.midY) / (rect.height / 2)
            return abs(hypot(x, y) - 1) <= tolerance / (min(rect.width, rect.height) / 2)
        case .arrow, .line, .pen, .highlighter:
            var segments = Array(zip(points, points.dropFirst()))
            if tool == .arrow, let start = points.first, let end = points.last {
                let angle = atan2(end.y - start.y, end.x - start.x), length = max(10, width * 4)
                for offset in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                    segments.append((end, CGPoint(x: end.x - length * cos(angle + offset), y: end.y - length * sin(angle + offset))))
                }
            }
            return segments.contains { a, b in
                let dx = b.x - a.x, dy = b.y - a.y
                let t = min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / max(0.001, dx * dx + dy * dy)))
                return hypot(point.x - a.x - t * dx, point.y - a.y - t * dy) <= tolerance
            }
        case .eraser: return false
        }
    }
    func moved(by delta: CGSize) -> Self {
        var copy = self
        copy.points = points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
        return copy
    }
    func resized(to target: CGRect) -> Self {
        let source = bounds
        let sx = target.width / max(1, source.width), sy = target.height / max(1, source.height)
        var copy = self
        copy.points = points.map { CGPoint(x: target.minX + ($0.x - source.minX) * sx, y: target.minY + ($0.y - source.minY) * sy) }
        if tool == .text {
            copy.fontSize = min(96, max(8, fontSize * min(sx, sy)))
            copy.textMaxWidth = max(1, target.width)
        } else if tool == .number { copy.width = min(40, max(3, width * min(sx, sy))) }
        return copy
    }
    static func constrainedEnd(from start: CGPoint, to end: CGPoint, tool: ScreenshotTool, within bounds: CGRect) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        var vector = CGPoint(x: dx, y: dy)
        if tool == .rectangle || tool == .ellipse {
            let side = max(abs(dx), abs(dy))
            vector = CGPoint(x: dx < 0 ? -side : side, y: dy < 0 ? -side : side)
        } else if tool == .arrow || tool == .line {
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            vector = CGPoint(x: hypot(dx, dy) * cos(angle), y: hypot(dx, dy) * sin(angle))
        }
        // Shorten along the constrained direction at a crop edge; do not break the angle/aspect ratio.
        var scale: CGFloat = 1
        if vector.x > 0 { scale = min(scale, (bounds.maxX - start.x) / vector.x) }
        if vector.x < 0 { scale = min(scale, (bounds.minX - start.x) / vector.x) }
        if vector.y > 0 { scale = min(scale, (bounds.maxY - start.y) / vector.y) }
        if vector.y < 0 { scale = min(scale, (bounds.minY - start.y) / vector.y) }
        return CGPoint(x: start.x + vector.x * scale, y: start.y + vector.y * scale)
    }
}


extension ScreenshotTool {
    var defaultWidth: Double {
        switch self {
        case .arrow: 4
        case .text: 17
        case .highlighter: 20
        case .mosaic: 16
        default: 5
        }
    }
    var widthRange: ClosedRange<Double> { self == .text ? 8...96 : 1...40 }
    func style(from styles: [String: ScreenshotAnnotationStyle]) -> ScreenshotAnnotationStyle {
        var style = styles[rawValue] ?? .init(width: defaultWidth)
        if !style.width.isFinite { style.width = defaultWidth }
        style.width = min(widthRange.upperBound, max(widthRange.lowerBound, style.width))
        if style.colorHex.count != 6 || UInt32(style.colorHex, radix: 16) == nil { style.colorHex = "D84A2F" }
        return style
    }
}
extension ScreenshotAnnotationStyle {
    var nsColor: NSColor {
        let rgb = UInt32(colorHex, radix: 16) ?? 0xD84A2F
        return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                       green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
}
