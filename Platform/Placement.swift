import Foundation

/// All geometry uses global screen coordinates with the primary display's top-left as origin.
public enum Placement {
    public enum Rule: String, Sendable { case below, above, right, edge, cursor }
    public struct Result: Equatable, Sendable {
        public let origin: CGPoint
        public let rule: Rule
    }

    public static func floating(selection: CGRect?, cursor: CGPoint, size: CGSize, screen: CGRect) -> Result {
        let minX = screen.minX + 12, maxX = screen.maxX - 12 - size.width
        let minY = screen.minY + 12, maxY = screen.maxY - 12 - size.height
        func x(_ value: CGFloat) -> CGFloat { max(minX, min(value, maxX)) }
        func y(_ value: CGFloat) -> CGFloat { max(minY, min(value, maxY)) }
        guard let selection else {
            return Result(origin: CGPoint(x: x(cursor.x + 12), y: y(cursor.y + 16)), rule: .cursor)
        }
        if selection.maxY + 8 <= maxY && selection.maxY + 8 >= minY {
            return Result(origin: CGPoint(x: x(selection.minX), y: selection.maxY + 8), rule: .below)
        }
        if selection.minY - 8 - size.height >= minY && selection.minY - 8 - size.height <= maxY {
            return Result(origin: CGPoint(x: x(selection.minX), y: selection.minY - 8 - size.height), rule: .above)
        }
        if selection.maxX + 8 <= maxX && selection.maxX + 8 >= minX {
            return Result(origin: CGPoint(x: selection.maxX + 8, y: y(selection.minY)), rule: .right)
        }
        return Result(origin: CGPoint(x: x(selection.minX), y: y(selection.maxY + 8)), rule: .edge)
    }

    /// Oversized windows are anchored at the top/left margin; callers must constrain their size.
    public static func panel(width: CGFloat, screen: CGRect) -> CGPoint {
        CGPoint(x: screen.minX + (screen.width - width) / 2, y: screen.minY + screen.height * 0.22)
    }
}
