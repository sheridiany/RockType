import Foundation
import Observation
import RoarkTPlatform

@MainActor @Observable final class ScreenshotBarcodes {
    enum Phase { case idle, running, done, failed, cancelled }
    private(set) var phase: Phase = .idle
    private(set) var codes: [BarcodeScanner.Code] = []
    private(set) var pendingURL: URL?
    @ObservationIgnored private let allowed: () -> Bool
    @ObservationIgnored private let recognize: @Sendable (Data) async throws -> [BarcodeScanner.Code]
    @ObservationIgnored private let open: (URL) -> Bool
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    init(allowed: @escaping () -> Bool, recognize: @escaping @Sendable (Data) async throws -> [BarcodeScanner.Code] = { try await BarcodeScanner().recognize($0) },
         open: @escaping (URL) -> Bool) {
        self.allowed = allowed; self.recognize = recognize; self.open = open
    }
    func clear() {
        generation += 1; task?.cancel(); task = nil; codes = []; pendingURL = nil; phase = .idle
    }
    func cancel() {
        pendingURL = nil
        guard phase == .running else { return }
        clear(); phase = .cancelled
    }
    func run(_ data: Data) {
        clear(); guard allowed() else { phase = .failed; return }
        let current = generation; phase = .running
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let codes = try await self.recognize(data)
                guard current == self.generation, !Task.isCancelled else { return }
                guard self.allowed() else { self.clear(); return }
                self.codes = codes; self.phase = .done; self.task = nil
            } catch {
                guard current == self.generation, !Task.isCancelled else { return }
                self.clear(); self.phase = .failed
            }
        }
    }
    func previewURL(at index: Int) {
        guard allowed(), codes.indices.contains(index) else { pendingURL = nil; return }
        pendingURL = codes[index].webURL
    }
    func dismissURL() { pendingURL = nil }
    @discardableResult func confirmURL() -> Bool {
        guard allowed(), let url = pendingURL else { pendingURL = nil; return false }
        pendingURL = nil
        return open(url)
    }
    isolated deinit { task?.cancel() }
}
