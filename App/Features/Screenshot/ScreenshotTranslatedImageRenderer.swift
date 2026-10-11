import AppKit
import RoarkTPlatform

/// Draw only inside OCR boxes. Never enlarge a box over a neighbouring line or fabricate missing text.
enum ScreenshotTranslatedImageRenderer {
    enum Failure: Error { case invalidRegions, textDoesNotFit, allocation }
    static func render(_ image: CGImage, lines: [OCR.Line], translations: [String]) throws -> CGImage {
        guard !lines.isEmpty, lines.count == translations.count,
              image.width <= 16_000, image.height <= 16_000,
              image.width * image.height <= 64_000_000 else { throw Failure.invalidRegions }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: image.width, pixelsHigh: image.height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
        guard let bitmap, let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw Failure.allocation }
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // Sample from the immutable original, not pixels already painted for another region.
        let original = NSBitmapImageRep(cgImage: image)
        for (line, text) in zip(lines, translations) {
            try Task.checkCancellation()
            let r = line.rect
            guard [r.minX, r.minY, r.width, r.height].allSatisfy(\.isFinite), r.width > 0, r.height > 0,
                  r.minX >= 0, r.minY >= 0, r.maxX <= 1.00001, r.maxY <= 1.00001,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.invalidRegions }
            let top = CGRect(x: r.minX * CGFloat(image.width), y: r.minY * CGFloat(image.height),
                width: r.width * CGFloat(image.width), height: r.height * CGFloat(image.height)).integral
                .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard !top.isNull, top.width >= 1, top.height >= 1 else { throw Failure.invalidRegions }
            let rect = CGRect(x: top.minX, y: CGFloat(image.height) - top.maxY, width: top.width, height: top.height)
            let background = sampleBackground(original, rect: top)
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byCharWrapping
            var size = min(72, rect.height * 0.82)
            var attributes: [NSAttributedString.Key: Any] = [:]
            var measured = CGRect.zero
            // Preserve every character; a region too dense at 4px fails the whole result instead of clipping.
            while size >= 4 {
                try Task.checkCancellation()
                attributes = [.font: NSFont.systemFont(ofSize: size), .paragraphStyle: paragraph,
                    .foregroundColor: background.redComponent * 0.2126 + background.greenComponent * 0.7152 + background.blueComponent * 0.0722 > 0.5 ? NSColor.black : NSColor.white]
                measured = (text as NSString).boundingRect(with: CGSize(width: max(1, rect.width - 2), height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
                if measured.height <= rect.height - 1 && measured.width <= rect.width - 1 { break }
                size -= 0.5
            }
            guard size >= 4 else { throw Failure.textDoesNotFit }
            context.saveGState(); context.clip(to: rect)
            background.setFill(); rect.fill()
            (text as NSString).draw(with: CGRect(x: rect.minX + 1, y: rect.minY + (rect.height - measured.height) / 2,
                width: max(1, rect.width - 2), height: measured.height), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
            context.restoreGState()
        }
        guard let output = bitmap.cgImage else { throw Failure.allocation }
        return output
    }
    /// Most frequent quantized perimeter colour resists a few foreground glyph pixels.
    private static func sampleBackground(_ bitmap: NSBitmapImageRep, rect: CGRect) -> NSColor {
        var bins: [Int: (count: Int, color: NSColor)] = [:]
        for index in 0..<32 {
            let t = CGFloat(index) / 31
            for point in [CGPoint(x: rect.minX + t * max(0, rect.width - 1), y: rect.minY),
                          CGPoint(x: rect.minX + t * max(0, rect.width - 1), y: rect.maxY - 1),
                          CGPoint(x: rect.minX, y: rect.minY + t * max(0, rect.height - 1)),
                          CGPoint(x: rect.maxX - 1, y: rect.minY + t * max(0, rect.height - 1))] {
                let x = min(bitmap.pixelsWide - 1, max(0, Int(point.x)))
                let y = min(bitmap.pixelsHigh - 1, max(0, Int(point.y)))
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let key = (Int(color.redComponent * 15) << 8) | (Int(color.greenComponent * 15) << 4) | Int(color.blueComponent * 15)
                bins[key] = ((bins[key]?.count ?? 0) + 1, color)
            }
        }
        return bins.max { $0.value.count < $1.value.count }?.value.color ?? .white
    }
}
