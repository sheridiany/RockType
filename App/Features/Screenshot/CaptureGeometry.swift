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
    static func globalScreenRect(_ selection: CGRect, screen: CGRect) -> CGRect {
        CGRect(x: screen.minX + selection.minX, y: screen.maxY - selection.maxY,
               width: selection.width, height: selection.height)
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

/// Geometry shared by the prototype's move/resize gestures and floating overlays.
enum ScreenshotHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    var title: String {
        switch self {
        case .topLeft: "左上"; case .top: "上"; case .topRight: "右上"; case .right: "右"
        case .bottomRight: "右下"; case .bottom: "下"; case .bottomLeft: "左下"; case .left: "左"
        }
    }
    var movesLeft: Bool { [.topLeft, .bottomLeft, .left].contains(self) }
    var movesRight: Bool { [.topRight, .bottomRight, .right].contains(self) }
    var movesTop: Bool { [.topLeft, .top, .topRight].contains(self) }
    var movesBottom: Bool { [.bottomLeft, .bottom, .bottomRight].contains(self) }
    func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: movesLeft ? rect.minX : movesRight ? rect.maxX : rect.midX,
                y: movesTop ? rect.minY : movesBottom ? rect.maxY : rect.midY)
    }
}


extension CaptureGeometry {
    static func nudged(_ rect: CGRect, direction: CaptureDirection, edge: CaptureEdge,
                       step: CGFloat, bounds: CGRect) -> CGRect {
        guard !rect.isEmpty else { return rect }
        let handle: ScreenshotHandle
        switch (direction, edge) {
        case (.left, .leading), (.right, .leading): handle = .left
        case (.left, .trailing), (.right, .trailing): handle = .right
        case (.up, .leading), (.down, .leading): handle = .top
        case (.up, .trailing), (.down, .trailing): handle = .bottom
        }
        return resized(rect, handle: handle, by: direction.delta(step: step), bounds: bounds)
    }
    static func toolbarFrame(selection: CGRect, bounds: CGRect) -> CGRect {
        let width = max(1, min(bounds.width - 16, 660)), height = min(94, bounds.height)
        let below = selection.maxY + 12, above = selection.minY - height - 12
        let y = below + height <= bounds.maxY - 8 ? below : above >= bounds.minY + 8 ? above : bounds.maxY - height - 8
        return CGRect(x: max(bounds.minX + 8, min(selection.maxX - width, bounds.maxX - width - 8)),
                      y: max(bounds.minY, y), width: width, height: height)
    }
}
