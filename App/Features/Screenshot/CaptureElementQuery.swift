import AppKit
import RoarkTPlatform

/// Independent of pixel capture: never await this controller before showing the overlay.
/// One worker at a time; timeout/cancel drops results without queuing unbounded AX work.
@MainActor final class CaptureElementQuery {
    typealias Reader = @Sendable (CGPoint) -> CaptureAccessibility.Snapshot?
    private let reader: Reader
    private let permitted: () -> Bool
    private let timeout: Duration
    private let queue = DispatchQueue(label: "screenshot.element-query", qos: .userInitiated)
    private var generation = 0
    private var busy = false
    private var deadline: ContinuousClock.Instant?
    private var completion: ((CaptureAccessibility.Snapshot?) -> Void)?
    private var timer: Task<Void, Never>?
    init(timeout: Duration = .milliseconds(120), permitted: @escaping () -> Bool = {
        !SecureInput.isSecureInputActive() && Accessibility.isTrusted()
    }, reader: @escaping Reader = CaptureAccessibility.snapshot) {
        self.timeout = timeout; self.permitted = permitted; self.reader = reader
    }
    func start(at point: CGPoint, completion: @escaping (CaptureAccessibility.Snapshot?) -> Void) {
        cancel()
        guard !busy, permitted() else { completion(nil); return }
        busy = true; self.completion = completion; deadline = .now + timeout
        let current = generation, reader = reader
        timer = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.deliver(nil, current: current)
        }
        queue.async { [weak self] in
            let result = reader(point)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.busy = false
                self.deliver(result, current: current)
            }
        }
    }
    func cancel() { generation += 1; completion = nil; deadline = nil; timer?.cancel(); timer = nil }
    private func deliver(_ result: CaptureAccessibility.Snapshot?, current: Int) {
        guard generation == current, let completion else { return }
        let withinBudget = deadline.map { ContinuousClock.now < $0 } ?? false
        self.completion = nil; deadline = nil; timer?.cancel(); timer = nil
        completion(withinBudget && permitted() ? result : nil)
    }
    isolated deinit { timer?.cancel() }
}
