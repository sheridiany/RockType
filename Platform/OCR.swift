import Foundation
import Vision
import ImageIO

public struct OCR: Sendable {
    public struct Line: Sendable, Equatable {
        public let text: String
        /// Normalized image coordinates (0...1), top-left origin; not screen coordinates.
        public let rect: CGRect
    }
    public struct Result: Sendable {
        public let lines: [Line]
        public var text: String { lines.map(\.text).joined(separator: "\n") }
    }
    public enum Failure: Error { case invalidImage, recognitionFailed }
    private let checkReadable: @MainActor @Sendable () throws -> Void

    public init() { checkReadable = { try SecureInput.requireReadable() } }
    init(checkReadable: @escaping @MainActor @Sendable () throws -> Void) { self.checkReadable = checkReadable }

    /// Runs Vision locally, away from the main actor. No network, disk writes or logging.
    public func recognize(_ data: Data) async throws -> Result {
        try Task.checkCancellation()
        try await checkReadable()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure.invalidImage }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.usesLanguageCorrection = true
            do { try VNImageRequestHandler(cgImage: image).perform([request]) }
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
        try await checkReadable()
        return result
    }
}
