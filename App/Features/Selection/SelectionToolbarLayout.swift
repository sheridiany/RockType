import Foundation

/// AppKit screen coordinates. Prefer an unobstructed edge, close to the release point.
enum SelectionToolbarLayout {
    static func frame(selection: CGRect?, cursor: CGPoint, size: CGSize, screen: CGRect) -> CGRect {
        let area = screen.insetBy(dx: 8, dy: 8)
        let size = CGSize(width: min(size.width, max(1, area.width)), height: min(size.height, max(1, area.height)))
        func fitted(_ point: CGPoint) -> CGRect {
            CGRect(x: max(area.minX, min(point.x, area.maxX - size.width)),
                   y: max(area.minY, min(point.y, area.maxY - size.height)), width: size.width, height: size.height)
        }
        guard let selection, [selection.minX, selection.minY, selection.width, selection.height].allSatisfy(\.isFinite),
              !selection.isEmpty, selection.intersects(screen) else {
            return fitted(CGPoint(x: cursor.x + 12, y: cursor.y - size.height - 12))
        }
        let selected = selection.intersection(screen)
        let x = max(selected.minX, min(cursor.x - 24, selected.maxX))
        let candidates = [CGPoint(x: x, y: selected.minY - size.height - 8),
                          CGPoint(x: x, y: selected.maxY + 8),
                          CGPoint(x: selected.maxX + 8, y: cursor.y - size.height / 2),
                          CGPoint(x: selected.minX - size.width - 8, y: cursor.y - size.height / 2)]
        return candidates.map(fitted).first(where: { !$0.intersects(selected) }) ?? fitted(candidates[0])
    }
}
