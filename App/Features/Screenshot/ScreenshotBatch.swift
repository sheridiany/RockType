import AppKit
import Observation

/// Explicit batch only; results and pixels remain in memory until the preview closes.
@MainActor @Observable final class ScreenshotBatch {
    nonisolated static let maximumCount = 10
    nonisolated static let maximumBytes = 128 * 1024 * 1024
    private(set) var sessions: [ScreenshotSession]
    private(set) var index = 0
    var current: ScreenshotSession { sessions[index] }
    init(sessions: [ScreenshotSession]) { precondition(!sessions.isEmpty); self.sessions = sessions }
    func select(_ index: Int) {
        guard sessions.indices.contains(index), self.index != index else { return }
        current.cancel(); self.index = index
        if !current.ocrFinished { current.runOCR() }
    }
    func close() {
        for session in sessions { session.onClose = {}; session.close() }
    }
    nonisolated static func load(_ urls: [URL]) throws -> [CGImage] {
        guard !urls.isEmpty, urls.count <= maximumCount else { throw ScreenshotImageImport.Failure.tooLarge }
        var images: [CGImage] = [], total = 0
        for url in urls {
            try Task.checkCancellation()
            let image = try ScreenshotImageImport.decode(ScreenshotImageImport.read(url))
            total += image.bytesPerRow * image.height
            guard total <= maximumBytes else { throw ScreenshotImageImport.Failure.tooLarge }
            images.append(image)
        }
        return images
    }
}
