import Foundation
import Vision
import ImageIO

/// Local Vision only. Coordinates match OCR.Line: normalized, top-left origin.
public struct BarcodeScanner: Sendable {
    public struct Code: Sendable, Equatable {
        public let payload: String
        public let symbology: String
        public let rect: CGRect
        public init(payload: String, symbology: String, rect: CGRect) {
            self.payload = payload; self.symbology = symbology; self.rect = rect
        }
        /// Only explicit web navigation is supported; never execute arbitrary URL schemes.
        public var webURL: URL? {
            guard !payload.isEmpty, !payload.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
                  let parts = URLComponents(string: payload),
                  ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
                  let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
            return parts.url
        }
    }
    public enum Failure: Error { case invalidImage, recognitionFailed }
    public init() {}
    public func recognize(_ data: Data) async throws -> [Code] {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure.invalidImage }
            let request = VNDetectBarcodesRequest()
            do {
                request.symbologies = try request.supportedSymbologies()
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch { throw Failure.recognitionFailed }
            try Task.checkCancellation()
            return (request.results ?? []).compactMap { observation -> Code? in
                guard let payload = observation.payloadStringValue, !payload.isEmpty else { return nil }
                let r = observation.boundingBox
                return Code(payload: payload, symbology: observation.symbology.rawValue,
                    rect: CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height))
            }.sorted { $0.rect.minY == $1.rect.minY ? $0.rect.minX < $1.rect.minX : $0.rect.minY < $1.rect.minY }
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
}
