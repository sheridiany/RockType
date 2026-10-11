// Frozen R1 reference from 3b6f55b; test-only baseline, not a production fallback.
import Foundation
import Vision
import ImageIO

public struct R1OCRBaseline: Sendable {
    public struct Line: Sendable, Equatable {
        public let text: String
        /// Normalized image coordinates (0...1), top-left origin; not screen coordinates.
        public let rect: CGRect
        public init(text: String, rect: CGRect) { self.text = text; self.rect = rect }
    }
    public struct Result: Sendable {
        public let lines: [Line]
        public init(lines: [Line]) { self.lines = lines }
        public var text: String { formatted() }
        public func formatted(paragraphs: Bool = false) -> String {
            guard !lines.isEmpty else { return "" }
            // Build rows before horizontal sorting; a fuzzy comparator is not transitive.
            var rows: [[Line]] = []
            for line in lines.sorted(by: { $0.rect.midY < $1.rect.midY }) {
                if let last = rows.last?.first,
                   abs(line.rect.midY - last.rect.midY) < min(line.rect.height, last.rect.height) * 0.5 {
                    rows[rows.count - 1].append(line)
                } else { rows.append([line]) }
            }
            let ordered = rows.flatMap { $0.sorted { $0.rect.minX < $1.rect.minX } }
            let left = ordered.map(\.rect.minX).min() ?? 0
            let unit = ordered.map { $0.rect.width / CGFloat(max(1, $0.text.count)) }.sorted()[ordered.count / 2]
            var output = ""
            var previous: Line?
            for line in ordered {
                let indent = min(32, max(0, Int(((line.rect.minX - left) / max(unit, 0.001)).rounded())))
                if let previous {
                    let sameRow = abs(line.rect.midY - previous.rect.midY) < min(line.rect.height, previous.rect.height) * 0.5
                    let gap = line.rect.minY - previous.rect.maxY
                    let list = line.text.range(of: #"^(?:[-*•]|\d+[.)])\s"#, options: .regularExpression) != nil
                    if sameRow { output += Self.separator(previous.text, line.text) }
                    else if gap > max(line.rect.height, previous.rect.height) * 0.9 { output += "\n\n" }
                    else if paragraphs && indent < 2 && !list && !previous.text.contains("{") && !previous.text.hasSuffix(";") {
                        output += Self.separator(previous.text, line.text)
                    } else { output += "\n" }
                }
                if output.isEmpty || output.hasSuffix("\n") { output += String(repeating: " ", count: indent) }
                output += line.text
                previous = line
            }
            return output
        }
        private static func separator(_ a: String, _ b: String) -> String {
            func cjk(_ c: Character?) -> Bool {
                c?.unicodeScalars.contains { (0x2E80...0x9FFF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) } ?? false
            }
            return cjk(a.last) && cjk(b.first) ? "" : " "
        }

    }
    public enum Failure: Error { case invalidImage, recognitionFailed }
    public init() {}

    /// Warm Vision with synthetic pixels only; never reads the screen.
    public static func prewarm() async {
        await Task.detached(priority: .utility) {
            guard let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let image = context.makeImage() else { return }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: image).perform([request])
        }.value
    }

    /// Bound the extra pixel budget; normalized boxes still refer to the original image.
    private static func upscaled(_ image: CGImage) -> CGImage {
        guard max(image.width, image.height) < 2400,
              let context = CGContext(data: nil, width: image.width * 2, height: image.height * 2,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width * 2, height: image.height * 2))
        return context.makeImage() ?? image
    }

    /// Runs Vision locally, away from the main actor. No network, disk writes or logging.
    public func recognize(_ data: Data, languages: [String] = ["zh-Hans", "en-US"]) async throws -> Result {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure.invalidImage }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            let supported = (try? request.supportedRecognitionLanguages()) ?? []
            request.recognitionLanguages = languages.filter { supported.contains($0) }
            request.automaticallyDetectsLanguage = true
            request.usesLanguageCorrection = true
            let prepared = Self.upscaled(image)
            do { try VNImageRequestHandler(cgImage: prepared).perform([request]) }
            catch { throw Failure.recognitionFailed }
            try Task.checkCancellation()
            return Result(lines: (request.results ?? []).compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let bounds = observation.boundingBox
                return Line(text: candidate.string, rect: CGRect(x: bounds.minX, y: 1 - bounds.maxY,
                                                                 width: bounds.width, height: bounds.height))
            })
        }
        let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        return result
    }
}
