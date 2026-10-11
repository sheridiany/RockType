import AppKit

/// All editing coordinates use a top-left origin in screen points. Export alone converts to pixels.
enum CaptureGeometry {
    static func selection(from start: CGPoint, to end: CGPoint, bounds: CGRect) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
    }
    static func moved(_ rect: CGRect, by delta: CGSize, bounds: CGRect) -> CGRect {
        CGRect(x: min(max(bounds.minX, rect.minX + delta.width), bounds.maxX - rect.width),
               y: min(max(bounds.minY, rect.minY + delta.height), bounds.maxY - rect.height),
               width: rect.width, height: rect.height)
    }
    static func resized(_ rect: CGRect, handle: ScreenshotHandle, by delta: CGSize, bounds: CGRect) -> CGRect {
        var l = rect.minX, r = rect.maxX, t = rect.minY, b = rect.maxY
        if handle.movesLeft { l = min(max(bounds.minX, l + delta.width), r - 1) }
        if handle.movesRight { r = max(min(bounds.maxX, r + delta.width), l + 1) }
        if handle.movesTop { t = min(max(bounds.minY, t + delta.height), b - 1) }
        if handle.movesBottom { b = max(min(bounds.maxY, b + delta.height), t + 1) }
        return CGRect(x: l, y: t, width: r - l, height: b - t)
    }
    /// Only geometry survives between captures; display removal or resizing must never create an invalid crop.
    static func restored(_ rect: CGRect, bounds: CGRect) -> CGRect {
        let clipped = rect.intersection(bounds)
        return clipped.isNull || clipped.isEmpty ? .zero : clipped
    }
    static func pixels(_ rect: CGRect, image: CGImage, size: CGSize) -> CGRect {
        let sx = CGFloat(image.width) / size.width, sy = CGFloat(image.height) / size.height
        return CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy)
            .integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
}
