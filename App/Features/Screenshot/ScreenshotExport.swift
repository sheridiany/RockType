import AppKit

/// Final output appearance. Input is already composited at the original pixel resolution.
enum ScreenshotExport {
    static func render(image: CGImage, pointSize: CGSize, roundedCorners: Bool) -> CGImage? {
        guard roundedCorners else { return image }
        guard pointSize.width > 0, pointSize.height > 0,
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let radius = min(8, min(pointSize.width, pointSize.height) / 2)
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius * CGFloat(image.width) / pointSize.width,
            cornerHeight: radius * CGFloat(image.height) / pointSize.height, transform: nil))
        context.clip(); context.draw(image, in: rect)
        return context.makeImage()
    }
    /// JPEG has no alpha channel: use a defined white background instead of accidental black corners.
    static func encode(_ image: CGImage, jpeg: Bool) -> Data? {
        var output = image
        if jpeg {
            guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.setFillColor(NSColor.white.cgColor); context.fill(rect); context.draw(image, in: rect)
            guard let flattened = context.makeImage() else { return nil }
            output = flattened
        }
        return NSBitmapImageRep(cgImage: output).representation(using: jpeg ? .jpeg : .png,
            properties: jpeg ? [.compressionFactor: 0.9] : [:])
    }
}
