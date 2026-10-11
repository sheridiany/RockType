import AppKit
import RoarkTPlatform

/// A frozen, bounded geometry snapshot. Hover/cycling never calls AX or retains AX objects.
struct CaptureSmartSelection {
    let windows: [CGRect]
    init(windows: [CGRect]) { self.windows = windows }
    private var snapshot: CaptureAccessibility.Snapshot?
    private(set) var chain: [CGRect] = []
    private(set) var index = 0
    var current: CGRect? { chain.indices.contains(index) ? chain[index] : nil }
    mutating func install(_ snapshot: CaptureAccessibility.Snapshot) { self.snapshot = snapshot; chain = []; index = 0 }
    mutating func update(at point: CGPoint) {
        guard let window = CaptureHitTesting.window(at: point, windows: windows) else { chain = []; index = 0; return }
        var candidates = [window]
        if let snapshot, snapshot.window == window {
            for rect in snapshot.rectangles where rect.width.isFinite && rect.height.isFinite && rect.minX.isFinite && rect.minY.isFinite {
                let clipped = rect.intersection(window)
                if !clipped.isEmpty, !clipped.isNull, clipped.contains(point), !candidates.contains(clipped) { candidates.append(clipped) }
            }
        }
        candidates.sort { $0.width * $0.height < $1.width * $1.height }
        var nested: [CGRect] = []
        for candidate in candidates where nested.last.map({ candidate.contains($0) }) ?? true { nested.append(candidate) }
        if chain != nested { chain = nested; index = 0 }
    }
    mutating func cycle(parent: Bool) { index = min(max(0, index + (parent ? 1 : -1)), max(0, chain.count - 1)) }
    static func local(_ snapshot: CaptureAccessibility.Snapshot, screen: CGRect, desktopTop: CGFloat) -> CaptureAccessibility.Snapshot {
        let screenTop = CGRect(x: screen.minX, y: desktopTop - screen.maxY, width: screen.width, height: screen.height)
        func local(_ rect: CGRect) -> CGRect { rect.intersection(screenTop).offsetBy(dx: -screenTop.minX, dy: -screenTop.minY) }
        return .init(window: local(snapshot.window).integral, rectangles: snapshot.rectangles.map(local))
    }
}
