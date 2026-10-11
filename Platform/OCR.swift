import Foundation
import Vision
import ImageIO
import CoreImage

public struct OCR: Sendable {
    public struct Line: Sendable, Equatable {
        public let text: String
        /// Normalized image coordinates (0...1), top-left origin; not screen coordinates.
        public let rect: CGRect
        public let confidence: Float
        public init(text: String, rect: CGRect, confidence: Float = 1) {
            self.text = text; self.rect = rect; self.confidence = confidence
        }
    }
    public struct Result: Sendable {
        public let lines: [Line]
        public init(lines: [Line]) { self.lines = lines }
        public var text: String { formatted() }
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

    /// Sample background luminance before choosing inversion. Mixed/light images stay untouched.
    static func contrastImage(_ image: CGImage, onlyDark: Bool) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: 32 * 32)
        let dark = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 32, height: 32, bitsPerComponent: 8,
                bytesPerRow: 32, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.setFillColor(gray: 1, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            return bytes.filter { $0 < 90 }.count > 32 * 32 * 3 / 4
        }
        guard dark || !onlyDark else { return image }
        var input = CIImage(cgImage: image)
        if dark { input = input.applyingFilter("CIColorInvert") }
        input = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.4])
        return CIContext(options: [.cacheIntermediates: false, .workingColorSpace: CGColorSpaceCreateDeviceRGB()]).createCGImage(input, from: input.extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()) ?? image
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
            var observations = request.results ?? []
            let confidence = observations.compactMap { $0.topCandidates(1).first?.confidence }
            if confidence.isEmpty || confidence.reduce(0, +) / Float(confidence.count) < 0.75 {
                let enhanced = Self.contrastImage(prepared, onlyDark: true)
                if enhanced !== prepared {
                    try Task.checkCancellation()
                    let second = VNRecognizeTextRequest()
                    second.recognitionLevel = .accurate; second.recognitionLanguages = request.recognitionLanguages
                    second.automaticallyDetectsLanguage = true; second.usesLanguageCorrection = true
                    try? VNImageRequestHandler(cgImage: enhanced).perform([second])
                    try Task.checkCancellation()
                    let candidates = second.results ?? []
                    func score(_ values: [VNRecognizedTextObservation]) -> Float {
                        values.compactMap { $0.topCandidates(1).first }.reduce(0) { $0 + $1.confidence * Float($1.string.count) }
                    }
                    if candidates.count >= observations.count, score(candidates) > score(observations) { observations = candidates }
                }
            }
            var lines = observations.flatMap { Self.fragments($0, image: prepared) }
            // Bounded second pass, only for uncertain lines. Never replaces with a lower-confidence guess.
            let uncertain = lines.indices.filter { lines[$0].confidence < 0.65 }
                .sorted { lines[$0].confidence < lines[$1].confidence }.prefix(3)
            for index in uncertain {
                try Task.checkCancellation()
                let line = lines[index]
                let pixels = CGRect(x: line.rect.minX * CGFloat(prepared.width), y: line.rect.minY * CGFloat(prepared.height),
                    width: line.rect.width * CGFloat(prepared.width), height: line.rect.height * CGFloat(prepared.height))
                    .insetBy(dx: -8, dy: -8).integral.intersection(CGRect(x: 0, y: 0, width: prepared.width, height: prepared.height))
                guard let crop = prepared.cropping(to: pixels) else { continue }
                let retry = VNRecognizeTextRequest()
                retry.recognitionLevel = .accurate; retry.recognitionLanguages = request.recognitionLanguages
                retry.automaticallyDetectsLanguage = true; retry.usesLanguageCorrection = false
                try? VNImageRequestHandler(cgImage: Self.upscaled(Self.contrastImage(crop, onlyDark: false))).perform([retry])
                try Task.checkCancellation()
                guard let observations = retry.results, observations.count == 1,
                      let best = observations[0].topCandidates(1).first,
                      best.confidence > line.confidence + 0.05,
                      best.string.count >= max(1, line.text.count / 2) else { continue }
                lines[index] = Line(text: best.string, rect: line.rect, confidence: best.confidence)
            }
            return Result(lines: lines)
        }
        let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        return result
    }

    /// Vision sometimes combines widely separated cells into a single observation.
    /// Word geometry recovers the actual gutter without inventing text.
    private static func fragments(_ observation: VNRecognizedTextObservation, image: CGImage) -> [Line] {
        guard let candidate = observation.topCandidates(1).first else { return [] }
        let text = candidate.string
        let words = text.split(separator: " ")
        var groups: [(text: String, rect: CGRect)] = []
        let minimumGap = observation.boundingBox.height * CGFloat(image.height) / CGFloat(image.width) * 1.8
        var search = text.startIndex
        for word in words {
            guard let range = text.range(of: String(word), range: search..<text.endIndex),
                  let box = try? candidate.boundingBox(for: range)?.boundingBox else {
                // Geometry is optional; never drop a word just because Vision omitted its box.
                let box = observation.boundingBox
                return [Line(text: text, rect: CGRect(x: box.minX, y: 1 - box.maxY,
                    width: box.width, height: box.height), confidence: candidate.confidence)]
            }
            search = range.upperBound
            if let last = groups.last, box.minX - last.rect.maxX < minimumGap {
                groups[groups.count - 1] = (last.text + " " + word, last.rect.union(box))
            } else { groups.append((String(word), box)) }
        }
        if groups.count <= 1 { groups = [(text, observation.boundingBox)] }
        return groups.map { group in
            Line(text: group.text, rect: CGRect(x: group.rect.minX, y: 1 - group.rect.maxY,
                width: group.rect.width, height: group.rect.height), confidence: candidate.confidence)
        }
    }
}
