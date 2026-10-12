import AppKit

/// Geometry only. A sweep is a capsule, so fast pointer motion cannot jump over a stroke.
enum ScreenshotEraser {
    struct Sweep: Sendable {
        var from: CGPoint
        var to: CGPoint
        var radius: CGFloat
        var bounds: CGRect {
            CGRect(x: min(from.x, to.x) - radius, y: min(from.y, to.y) - radius,
                   width: abs(to.x - from.x) + 2 * radius, height: abs(to.y - from.y) + 2 * radius)
        }
        func clipped(to rect: CGRect) -> Self? {
            guard let interval = ScreenshotEraser.rectangleInterval(from, to, rect) else { return nil }
            return Self(from: ScreenshotEraser.point(from, to, interval.0),
                        to: ScreenshotEraser.point(from, to, interval.1), radius: radius)
        }
    }
    struct Removal: Sendable { let annotation: ScreenshotAnnotation; let sweep: Sweep }
    struct Result: Sendable {
        var items: [ScreenshotAnnotation]
        var removed: [Removal] = []
    }
    static func erase(_ items: [ScreenshotAnnotation], sweeps: [Sweep]) throws -> Result {
        var result = Result(items: items)
        for sweep in sweeps {
            try Task.checkCancellation()
            var next: [ScreenshotAnnotation] = []
            for item in result.items {
                try Task.checkCancellation()
                guard hitBounds(item).intersects(sweep.bounds) else {
                    next.append(item); continue
                }
                if item.tool == .pen || item.tool == .highlighter {
                    for points in try split(item.points, by: sweep, width: item.width, roundedCaps: item.tool != .highlighter) {
                        var part = item; part.points = points; next.append(part)
                    }
                } else if try hits(item, sweep: sweep) { result.removed.append(Removal(annotation: item, sweep: sweep)) }
                else { next.append(item) }
            }
            result.items = next
        }
        return result
    }
    static func hovered(_ items: [ScreenshotAnnotation], sweep: Sweep) throws -> Set<Int> {
        var found: Set<Int> = []
        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            if try hits(item, sweep: sweep) { found.insert(index) }
        }
        return found
    }
    static func hits(_ item: ScreenshotAnnotation, sweep: Sweep) throws -> Bool {
        guard !item.points.isEmpty,
              hitBounds(item).intersects(sweep.bounds) else { return false }
        if item.tool == .number {
            return capsuleInterval(item.points[0], item.points[0], sweep, extra: max(12, item.width * 4)) != nil
        }
        if [.text, .mosaic].contains(item.tool), item.bounds.contains(sweep.from) || item.bounds.contains(sweep.to) { return true }
        let paths = outlines(item)
        let extra: CGFloat = [.text, .mosaic].contains(item.tool) ? 0 : item.width / 2
        for path in paths {
            if path.count == 1, capsuleInterval(path[0], path[0], sweep, extra: extra) != nil { return true }
            for (index, pair) in zip(path, path.dropFirst()).enumerated() {
                if index % 512 == 0 { try Task.checkCancellation() }
                let interval = item.tool == .highlighter
                    ? highlighterInterval(pair.0, pair.1, sweep, width: item.width)
                    : capsuleInterval(pair.0, pair.1, sweep, extra: extra)
                if interval != nil { return true }
            }
        }
        return false
    }
    /// Only the removed centreline intervals are discarded. Intersections are analytic, not point samples.
    static func split(_ points: [CGPoint], by sweep: Sweep, width: CGFloat, roundedCaps: Bool = true) throws -> [[CGPoint]] {
        guard let first = points.first else { return [] }
        if points.allSatisfy({ $0 == first }) {
            return capsuleInterval(first, first, sweep, extra: width / 2) == nil ? [points] : []
        }
        var fragments: [[CGPoint]] = [], current: [CGPoint] = []
        var changed = false
        func append(_ p: CGPoint) { if current.last != p { current.append(p) } }
        func flush() { if current.count > 1 { fragments.append(current) }; current.removeAll(keepingCapacity: true) }
        for (index, pair) in zip(points, points.dropFirst()).enumerated() {
            if index % 512 == 0 { try Task.checkCancellation() }
            let (a, b) = pair
            let interval = roundedCaps ? capsuleInterval(a, b, sweep, extra: width / 2) : highlighterInterval(a, b, sweep, width: width)
            guard let (lo, hi) = interval, hi - lo > 1e-9 else {
                append(a); append(b); continue
            }
            changed = true
            if lo > 1e-9 { append(a); append(point(a, b, lo)) }
            flush()
            if hi < 1 - 1e-9 { append(point(a, b, hi)); append(b) }
        }
        flush(); return changed ? fragments : [points]
    }
    private static func hitBounds(_ item: ScreenshotAnnotation) -> CGRect {
        let padding = item.tool == .arrow ? max(10, item.width * 4) + item.width / 2 : item.width / 2
        return item.bounds.insetBy(dx: -padding, dy: -padding)
    }
    private static func outlines(_ item: ScreenshotAnnotation) -> [[CGPoint]] {
        let r = item.rect
        switch item.tool {
        case .rectangle:
            let radius = min(8, min(r.width, r.height) / 2)
            var points: [CGPoint] = []
            let centers = [CGPoint(x: r.maxX - radius, y: r.minY + radius), CGPoint(x: r.maxX - radius, y: r.maxY - radius),
                           CGPoint(x: r.minX + radius, y: r.maxY - radius), CGPoint(x: r.minX + radius, y: r.minY + radius)]
            for (corner, center) in centers.enumerated() {
                for step in 0...8 {
                    let angle = (-CGFloat.pi / 2) + CGFloat(corner) * .pi / 2 + CGFloat(step) * .pi / 16
                    points.append(CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
                }
            }
            return [points + points.prefix(1)]
        case .ellipse:
            let count = max(32, min(512, Int(ceil(.pi * max(r.width, r.height) / 3))))
            return [(0...count).map { i in
                let angle = CGFloat(i) * 2 * .pi / CGFloat(count)
                return CGPoint(x: r.midX + r.width / 2 * cos(angle), y: r.midY + r.height / 2 * sin(angle))
            }]
        case .text, .mosaic:
            let box = item.bounds
            return [[CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                     CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.minX, y: box.minY)]]
        case .arrow:
            guard let a = item.points.first, let b = item.points.last else { return [] }
            let angle = atan2(b.y - a.y, b.x - a.x), length = max(10, item.width * 4)
            return [[a, b]] + [-CGFloat.pi / 6, CGFloat.pi / 6].map {
                [b, CGPoint(x: b.x - length * cos(angle + $0), y: b.y - length * sin(angle + $0))]
            }
        case .eraser: return []
        default: return [item.points]
        }
    }
    private static func point(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
    private static func rectangleInterval(_ a: CGPoint, _ b: CGPoint, _ rect: CGRect) -> (CGFloat, CGFloat)? {
        var lo: CGFloat = 0, hi: CGFloat = 1
        for (origin, delta, low, high) in [(a.x, b.x - a.x, rect.minX, rect.maxX), (a.y, b.y - a.y, rect.minY, rect.maxY)] {
            if abs(delta) < 1e-12 { if origin < low || origin > high { return nil } }
            else {
                let t0 = (low - origin) / delta, t1 = (high - origin) / delta
                lo = max(lo, min(t0, t1)); hi = min(hi, max(t0, t1))
                if lo > hi { return nil }
            }
        }
        return (lo, hi)
    }
    /// Project the swept capsule clipped to a flat-capped stroke's width band.
    /// Unlike a pen, a highlighter needs no extra cut length to clear newly rounded end caps.
    private static func highlighterInterval(_ a: CGPoint, _ b: CGPoint, _ sweep: Sweep, width: CGFloat) -> (CGFloat, CGFloat)? {
        let dx = b.x - a.x, dy = b.y - a.y, length = hypot(dx, dy)
        guard length > 1e-9 else { return capsuleInterval(a, b, sweep, extra: width / 2) }
        func project(_ p: CGPoint) -> CGPoint {
            let x = p.x - a.x, y = p.y - a.y
            return CGPoint(x: (x * dx + y * dy) / length, y: (-x * dy + y * dx) / length)
        }
        let from = project(sweep.from), to = project(sweep.to), radius = sweep.radius, half = width / 2
        var values: [CGFloat] = []
        for p in [from, to] {
            let distance = max(0, abs(p.y) - half)
            if distance <= radius {
                let extent = sqrt(max(0, radius * radius - distance * distance))
                values += [p.x - extent, p.x + extent]
            }
        }
        let sx = to.x - from.x, sy = to.y - from.y, sweepLength = hypot(sx, sy)
        if sweepLength > 1e-9 {
            for sign: CGFloat in [-1, 1] {
                let offset = CGPoint(x: -sy / sweepLength * radius * sign, y: sx / sweepLength * radius * sign)
                let start = CGPoint(x: from.x + offset.x, y: from.y + offset.y)
                var lo: CGFloat = 0, hi: CGFloat = 1
                if abs(sy) < 1e-12 {
                    if abs(start.y) > half { continue }
                } else {
                    let t0 = (-half - start.y) / sy, t1 = (half - start.y) / sy
                    lo = max(0, min(t0, t1)); hi = min(1, max(t0, t1))
                }
                if lo <= hi { values += [start.x + lo * sx, start.x + hi * sx] }
            }
        }
        guard let low = values.min(), let high = values.max() else { return nil }
        let lo = max(0, low / length), hi = min(1, high / length)
        return lo <= hi ? (lo, hi) : nil
    }
    private static func capsuleInterval(_ a: CGPoint, _ b: CGPoint, _ sweep: Sweep, extra: CGFloat) -> (CGFloat, CGFloat)? {
        let radius = sweep.radius + extra
        let bounds = sweep.bounds.insetBy(dx: -extra, dy: -extra)
        if max(a.x, b.x) < bounds.minX || min(a.x, b.x) > bounds.maxX || max(a.y, b.y) < bounds.minY || min(a.y, b.y) > bounds.maxY { return nil }
        let dx = b.x - a.x, dy = b.y - a.y, lengthSquared = dx * dx + dy * dy
        var intervals: [(CGFloat, CGFloat)] = []
        for center in [sweep.from, sweep.to] {
            let x = a.x - center.x, y = a.y - center.y
            let c = x * x + y * y - radius * radius
            if lengthSquared < 1e-12 {
                if c <= 0 { intervals.append((0, 1)) }
            } else {
                let dot = x * dx + y * dy, discriminant = dot * dot - lengthSquared * c
                if discriminant >= 0 {
                    let root = sqrt(discriminant)
                    let lo = max(0, (-dot - root) / lengthSquared), hi = min(1, (-dot + root) / lengthSquared)
                    if lo <= hi { intervals.append((lo, hi)) }
                }
            }
        }
        let sx = sweep.to.x - sweep.from.x, sy = sweep.to.y - sweep.from.y, length = hypot(sx, sy)
        if length > 1e-9 {
            func projected(_ p: CGPoint) -> CGPoint {
                let x = p.x - sweep.from.x, y = p.y - sweep.from.y
                return CGPoint(x: (x * sx + y * sy) / length, y: (-x * sy + y * sx) / length)
            }
            if let interval = rectangleInterval(projected(a), projected(b), CGRect(x: 0, y: -radius, width: length, height: radius * 2)) {
                intervals.append(interval)
            }
        }
        guard let lo = intervals.map(\.0).min(), let hi = intervals.map(\.1).max() else { return nil }
        return (lo, hi)
    }
}

/// One drag owns one eventual history entry. Pending sweeps retain bends and execute in order off the UI executor.
@MainActor final class ScreenshotEraseSession {
    private(set) var items: [ScreenshotAnnotation]
    private var pending: [ScreenshotEraser.Sweep] = []
    private var task: Task<Void, Never>?
    private(set) var ending = false
    private var cancelled = false
    var allowed: () -> Bool = { true }
    var onChange: (ScreenshotEraser.Result) -> Void = { _ in }
    var onFinish: ([ScreenshotAnnotation]) -> Void = { _ in }
    var onDenied: () -> Void = {}
    init(items: [ScreenshotAnnotation]) { self.items = items }
    func append(_ sweep: ScreenshotEraser.Sweep) {
        guard !ending, !cancelled else { return }
        pending.append(sweep); pump()
    }
    func finish() { ending = true; pump() }
    func cancel() {
        cancelled = true; task?.cancel(); task = nil; pending.removeAll(); items.removeAll()
        onChange = { _ in }; onFinish = { _ in }; onDenied = {}
    }
    private func pump() {
        guard !cancelled, task == nil else { return }
        guard allowed() else { let denied = onDenied; cancel(); denied(); return }
        guard !pending.isEmpty else { if ending { onFinish(items) }; return }
        let batch = Array(pending.prefix(16)), snapshot = items
        pending.removeFirst(batch.count)
        task = Task { [weak self] in
            let work = Task.detached(priority: .userInitiated) { try ScreenshotEraser.erase(snapshot, sweeps: batch) }
            let result = await withTaskCancellationHandler(operation: { try? await work.value }, onCancel: { work.cancel() })
            guard let self, !Task.isCancelled, !self.cancelled else { return }
            self.task = nil
            guard self.allowed() else { let denied = self.onDenied; self.cancel(); denied(); return }
            if let result { self.items = result.items; self.onChange(result) }
            self.pump()
        }
    }
    deinit { task?.cancel() }
}
