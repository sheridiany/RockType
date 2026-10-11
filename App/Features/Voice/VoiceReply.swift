import Foundation

/// One reply gate per XPC call; completion, timeout and cancellation race to settle it once.
@MainActor
final class VoiceReply<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, any Error>?
    private var timer: Task<Void, Never>?
    func wait(seconds: Double, send: (VoiceReply<Value>) -> Void) async throws -> Value {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                timer = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                    self?.finish(.failure(VoiceFailure.timeout))
                }
                send(self)
            }
        } onCancel: { Task { @MainActor in self.finish(.failure(CancellationError())) } }
    }
    func finish(_ result: Result<Value, any Error>) {
        guard let continuation else { return }
        self.continuation = nil; timer?.cancel(); timer = nil
        continuation.resume(with: result)
    }
}
