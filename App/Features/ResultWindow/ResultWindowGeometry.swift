import AppKit

/// Stores geometry only, never source identity or content. Shared by result controllers.
@MainActor final class ResultWindowGeometry {
    static let shared = ResultWindowGeometry(defaults: .standard)
    private let defaults: UserDefaults?
    private(set) var frame: CGRect?
    private let key = "resultWindowGeometry"
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        if let values = defaults?.array(forKey: key) as? [Double], values.count == 4,
           values.allSatisfy(\.isFinite), values[2] >= 300, values[3] >= 240 {
            frame = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
    }
    func remember(_ rect: CGRect) {
        guard [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite),
              rect.width >= 300, rect.height >= 240 else { return }
        frame = rect
        defaults?.set([rect.minX, rect.minY, rect.width, rect.height], forKey: key)
    }
    static func avoiding(_ preferred: CGRect, occupied: [CGRect], screen: CGRect) -> CGRect {
        let original = fitted(preferred, in: screen)
        guard occupied.contains(where: { $0.intersects(original) }) else { return original }
        var candidates = [original]
        for rect in occupied {
            for point in [CGPoint(x: rect.maxX + 12, y: original.minY),
                          CGPoint(x: rect.minX - original.width - 12, y: original.minY),
                          CGPoint(x: original.minX, y: rect.minY - original.height - 12),
                          CGPoint(x: original.minX, y: rect.maxY + 12)] {
                candidates.append(fitted(CGRect(origin: point, size: original.size), in: screen))
            }
        }
        func obstruction(_ candidate: CGRect) -> CGFloat {
            let title = CGRect(x: candidate.minX, y: candidate.maxY - 44, width: candidate.width, height: 44)
            return occupied.reduce(0) { total, rect in
                let overlap = candidate.intersection(rect), header = title.intersection(rect)
                return total + (overlap.isNull ? 0 : overlap.width * overlap.height)
                    + (header.isNull ? 0 : header.width * header.height * 10)
            }
        }
        return candidates.min(by: { obstruction($0) < obstruction($1) }) ?? original
    }

    static func fitted(_ rect: CGRect, in screen: CGRect) -> CGRect {
        let area = screen.insetBy(dx: min(12, screen.width / 4), dy: min(12, screen.height / 4))
        let size = CGSize(width: min(rect.width, area.width), height: min(rect.height, area.height))
        return CGRect(x: min(max(rect.minX, area.minX), area.maxX - size.width),
                      y: min(max(rect.minY, area.minY), area.maxY - size.height), width: size.width, height: size.height)
    }
}
