import Foundation
import CoreGraphics

/// Owns only accepted strips and row features, never a queue of full input frames.
actor ScrollStitcher: ScrollStitching {
    enum Failure: Error { case empty, image, dimensions }
    private struct Strip {
        let bytes: Data
        var rows: Range<Int>
    }
    private struct Features {
        let bytes: [UInt8]
        let hashes: [UInt64]
        let columns: Int
        let height: Int
        func error(_ row: Int, _ other: Features, _ otherRow: Int, stride: Int = 1) -> Double {
            var sum = 0, count = 0
            for x in Swift.stride(from: 0, to: columns, by: stride) {
                for c in 0..<3 {
                    sum += abs(Int(bytes[(row * columns + x) * 3 + c]) - Int(other.bytes[(otherRow * columns + x) * 3 + c]))
                    count += 1
                }
            }
            return Double(sum) / Double(max(1, count) * 255)
        }
    }
    private let limits: ScrollStitchLimits
    private var width = 0, frameHeight = 0, height = 0, count = 0
    private var top = 0, bottom = 0
    private var previous: Features?
    private var strips: [Strip] = []
    private var footer: Data?
    private var preview: CGImage?
    init(limits: ScrollStitchLimits = .init()) { self.limits = limits }
    func reset() { strips.removeAll(); footer = nil; previous = nil; preview = nil; width = 0; frameHeight = 0; height = 0; count = 0; top = 0; bottom = 0 }

    func append(_ image: CGImage) throws -> ScrollStitchUpdate {
        try Task.checkCancellation()
        let w = image.width, h = image.height
        guard w > 0, h >= 32, w <= 16_384, h <= 8_192 else { throw Failure.dimensions }
        if count > 0, w != width || h != frameHeight { throw Failure.dimensions }
        guard limits.maxBytes > 0, image.bytesPerRow <= limits.maxBytes / h else { return update(.limit) }
        let inputBytes = max(w * h * 4, image.bytesPerRow * h)
        // Reserve before decoding, including incoming surface, normalization, features and thumbnail.
        guard fits(input: inputBytes, featureBytes: (min(w, 32) * 6 + 16) * h, retained: retainedBytes + (count == 0 ? inputBytes : 0)), h <= limits.maxHeight, limits.maxFrames > 0 else {
            return update(.limit)
        }
        let bytes = try normalize(image)
        let features = try Self.features(bytes, width: w, height: h)
        guard let previous else {
            width = w; frameHeight = h; height = h; count = 1
            strips = [.init(bytes: bytes, rows: 0..<h)]; self.previous = features
            return update(.started)
        }
        let sameRows = zip(previous.hashes, features.hashes).reduce(0) { $0 + ($1.0 == $1.1 ? 1 : 0) }
        if sameRows * 100 >= h * 98 { return update(.unchanged) }
        // Evaluate stationary changes over the whole viewport, before mistaking still margins for sticky bands.
        if sameRows * 4 >= h * 3 {
            var stationaryError = 0.0
            for y in 0..<h {
                if y % 64 == 0 { try Task.checkCancellation() }
                stationaryError += previous.error(y, features, y)
            }
            if stationaryError / Double(h) < 0.018 { return update(.unchanged) }
        }
        if count >= limits.maxFrames { return update(.limit) }
        var header = 0, tail = 0
        while header < h / 3, previous.hashes[header] == features.hashes[header] { header += 1 }
        while tail < h / 3, previous.hashes[h - tail - 1] == features.hashes[h - tail - 1] { tail += 1 }
        if count > 1 {
            guard (0..<top).allSatisfy({ previous.error($0, features, $0) < 0.01 }),
                  (0..<bottom).allSatisfy({ previous.error(h - $0 - 1, features, h - $0 - 1) < 0.01 }) else { return update(.ambiguous) }
        }
        header = max(header, top); tail = max(tail, bottom)
        let start = header, end = h - tail, body = end - start
        let overlap = max(24, body / 4), maximum = body - overlap
        guard maximum > 0 else { return update(.ambiguous) }
        // Full-width row fingerprints resolve ordinary repeated text layouts without sparse-column aliasing.
        var exact: Int?
        for d in -maximum...maximum where d != 0 {
            if d % 32 == 0 { try Task.checkCancellation() }
            let lo = max(start, start - d), hi = min(end, end - d)
            guard (0..<16).allSatisfy({ i in
                let y = lo + (hi - lo - 1) * i / 15
                return previous.hashes[y + d] == features.hashes[y]
            }) else { continue }
            var same = true
            for y in lo..<hi {
                if y % 256 == 0 { try Task.checkCancellation() }
                if previous.hashes[y + d] != features.hashes[y] { same = false; break }
            }
            if same {
                if exact != nil { return update(.ambiguous) }
                exact = d
            }
        }
        let best: (offset: Int, score: Double)
        if let exact { best = (exact, 0) }
        else {
            // Score a bounded set of row anchors first; fully confirm every plausible candidate.
            var candidates: [(offset: Int, score: Double)] = []
            for offset in -maximum...maximum {
                if offset % 32 == 0 { try Task.checkCancellation() }
                let lower = max(start, start - offset), upper = min(end, end - offset)
                var error = 0.0
                for i in 0..<16 {
                    let y = lower + (upper - lower - 1) * i / 15
                    error += previous.error(y + offset, features, y, stride: 2)
                }
                error /= 16
                if error < 0.035 { candidates.append((offset, error)) }
            }
            guard !candidates.isEmpty else { return update(.gap) }
            candidates.sort { $0.score < $1.score }
            // Blank / repeating pages can have thousands of equally plausible shifts. Never guess.
            let cutoff = min(0.035, candidates[0].score + 0.012)
            candidates = candidates.filter { $0.score <= cutoff }
            guard candidates.count <= 32 else { return update(.ambiguous) }
            var confirmed: [(offset: Int, score: Double)] = []
            for candidate in candidates {
                try Task.checkCancellation()
                let d = candidate.offset, lower = max(start, start - d), upper = min(end, end - d)
                var error = 0.0, informative = 0
                for y in lower..<upper {
                    if y % 256 == 0 { try Task.checkCancellation() }
                    error += previous.error(y + d, features, y)
                    if y + 1 < upper, features.error(y, features, y + 1) > 0.005 { informative += 1 }
                }
                guard informative >= max(8, (upper - lower) / 20) else { continue }
                confirmed.append((d, error / Double(upper - lower)))
            }
            confirmed.sort { $0.score < $1.score }
            guard let candidate = confirmed.first, candidate.score < 0.018 else { return update(.gap) }
            if confirmed.dropFirst().contains(where: { $0.score - candidate.score < 0.003 }) { return update(.ambiguous) }
            best = candidate
        }
        if best.offset == 0 { return update(.unchanged) }
        guard best.offset > 0 else { return update(.reversed) }
        let added = best.offset, newHeight = height + added
        // A true fixed band disagrees with the MOVING correspondence. Identical blank page margins do not.
        var fixedTop = top, fixedBottom = bottom
        for y in 0..<header where y + added < h {
            if previous.hashes[y + added] != features.hashes[y] { fixedTop = max(fixedTop, y + 1) }
        }
        for y in (h - tail)..<h where y >= added {
            if previous.hashes[y] != features.hashes[y - added] { fixedBottom = max(fixedBottom, h - y) }
        }
        let appendEnd = h - fixedBottom
        let newRetained = retainedBytes + added * w * 4 + (fixedBottom - bottom) * w * 4
        guard newHeight <= limits.maxHeight, fits(input: inputBytes, featureBytes: (min(w, 32) * 6 + 16) * h,
            retained: newRetained + fixedBottom * w * 4) else { return update(.limit) }
        try Task.checkCancellation()
        let next = bytes.subdata(in: ((appendEnd - added) * w * 4)..<(appendEnd * w * 4))
        let nextFooter = fixedBottom == 0 ? nil : bytes.subdata(in: (appendEnd * w * 4)..<bytes.count)
        var trim = fixedBottom - bottom
        while trim > 0, !strips.isEmpty {
            let index = strips.count - 1, remove = min(trim, strips[index].rows.count)
            strips[index].rows = strips[index].rows.lowerBound..<(strips[index].rows.upperBound - remove)
            trim -= remove
            if strips[index].rows.isEmpty { strips.removeLast() }
        }
        top = fixedTop; bottom = fixedBottom
        strips.append(.init(bytes: next, rows: 0..<added)); footer = nextFooter
        self.previous = features; height = newHeight; count += 1
        return update(.added)
    }
    private var retainedBytes: Int { strips.reduce(0) { $0 + $1.bytes.count } + (footer?.count ?? 0) }
    private func fits(input: Int, featureBytes: Int, retained: Int) -> Bool {
        // Covers decoding while strips exist, or final contiguous output while strips still exist.
        // Reserve both feature arrays plus thumbnail buffers and small bookkeeping.
        max(2 * input + retained, 2 * retained) + featureBytes + 2 * 1024 * 1024 <= limits.maxBytes
    }
    private func update(_ outcome: ScrollStitchUpdate.Outcome) -> ScrollStitchUpdate {
        if outcome == .started || outcome == .added { preview = thumbnail() }
        return .init(outcome: outcome, height: height, thumbnail: preview)
    }
    private var outputStrips: [Strip] {
        strips + (footer.map { [.init(bytes: $0, rows: 0..<bottom)] } ?? [])
    }
    func finish() throws -> CGImage {
        try Task.checkCancellation()
        guard width > 0, height > 0 else { throw Failure.empty }
        let size = width * height * 4
        guard let data = CFDataCreateMutable(nil, size) else { throw Failure.image }
        CFDataSetLength(data, size)
        guard let output = CFDataGetMutableBytePtr(data) else { throw Failure.image }
        var destination = 0
        for strip in outputStrips {
            try Task.checkCancellation()
            let begin = strip.rows.lowerBound * width * 4, length = strip.rows.count * width * 4
            strip.bytes.withUnsafeBytes { raw in
                output.advanced(by: destination).update(from: raw.bindMemory(to: UInt8.self).baseAddress!.advanced(by: begin), count: length)
            }
            destination += length
        }
        guard destination == size, let image = Self.image(data, width: width, height: height) else { throw Failure.image }
        return image
    }
    private func thumbnail() -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let factor = min(1, min(180.0 / Double(width), 540.0 / Double(height)))
        let w = max(1, Int(Double(width) * factor)), h = max(1, Int(Double(height) * factor))
        var bytes = Data(count: w * h * 4)
        let pieces = outputStrips
        bytes.withUnsafeMutableBytes { destination in
            let output = destination.bindMemory(to: UInt8.self)
            var index = 0, base = 0
            for y in 0..<h {
                let sourceY = y * height / h
                while index + 1 < pieces.count, sourceY >= base + pieces[index].rows.count { base += pieces[index].rows.count; index += 1 }
                let strip = pieces[index], row = strip.rows.lowerBound + sourceY - base
                strip.bytes.withUnsafeBytes { source in
                    let input = source.bindMemory(to: UInt8.self)
                    for x in 0..<w {
                        let src = (row * width + x * width / w) * 4, dst = (y * w + x) * 4
                        for c in 0..<4 { output[dst + c] = input[src + c] }
                    }
                }
            }
        }
        return Self.image(bytes as CFData, width: w, height: h)
    }
    private static func image(_ data: CFData, width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).union(.byteOrder32Big),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
    private func normalize(_ image: CGImage) throws -> Data {
        var bytes = Data(count: image.width * image.height * 4)
        let success = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.setBlendMode(.copy); context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); return true
        }
        guard success else { throw Failure.image }; return bytes
    }
    private static func features(_ data: Data, width: Int, height: Int) throws -> Features {
        let columns = min(32, width)
        var result = [UInt8](repeating: 0, count: height * columns * 3)
        var hashes = [UInt64](repeating: 0, count: height)
        try data.withUnsafeBytes { raw in
            let pixels = raw.bindMemory(to: UInt8.self)
            let words = raw.bindMemory(to: UInt32.self)
            for y in 0..<height {
                if y % 32 == 0 { try Task.checkCancellation() }
                var hash: UInt64 = 14695981039346656037
                for x in 0..<width { hash = (hash ^ UInt64(words[y * width + x])) &* 1099511628211 }
                hashes[y] = hash
                for x in 0..<columns {
                    let source = (y * width + (2 * x + 1) * width / (2 * columns)) * 4
                    for c in 0..<3 { result[(y * columns + x) * 3 + c] = pixels[source + c] }
                }
            }
        }
        return .init(bytes: result, hashes: hashes, columns: columns, height: height)
    }
}
