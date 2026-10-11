import AppKit

/// Shared precedence for drawing, selecting and double-click completion.
enum CaptureHitTesting {
    static func handle(at point: CGPoint, rect: CGRect, radius: CGFloat) -> ScreenshotHandle? {
        guard !rect.isEmpty else { return nil }
        return ScreenshotHandle.allCases.first {
            let handle = $0.point(in: rect)
            return hypot(handle.x - point.x, handle.y - point.y) <= radius
        }
    }
    static func annotation(at point: CGPoint, items: [ScreenshotAnnotation]) -> Int? {
        items.indices.reversed().first { items[$0].contains(point) }
    }
    static func text(at point: CGPoint, items: [ScreenshotAnnotation], selection: CGRect) -> Int? {
        items.indices.reversed().first {
            items[$0].tool == .text && items[$0].bounds.intersection(selection).contains(point)
        }
    }
    static func window(at point: CGPoint, windows: [CGRect]) -> CGRect? {
        windows.first { $0.contains(point) }
    }
}
