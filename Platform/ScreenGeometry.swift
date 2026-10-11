import AppKit

@MainActor public enum ScreenGeometry {
    public struct Screen: Equatable, Sendable {
        public let frame: CGRect
        public let visibleFrame: CGRect
        public let scale: CGFloat
    }

    public static func topLeft(_ point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    public static func topLeft(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static var mousePosition: CGPoint {
        topLeft(NSEvent.mouseLocation, primaryHeight: NSScreen.screens.first?.frame.maxY ?? 0)
    }

    public static func screen(containing point: CGPoint) -> Screen? {
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        return NSScreen.screens.compactMap { screen -> Screen? in
            let frame = topLeft(screen.frame, primaryHeight: height)
            guard frame.contains(point) else { return nil }
            return Screen(frame: frame, visibleFrame: topLeft(screen.visibleFrame, primaryHeight: height),
                          scale: screen.backingScaleFactor)
        }.first
    }
}
