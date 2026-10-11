import Foundation
import MLX
import MLXAudioSTT

private final class Reply<T>: @unchecked Sendable {
    let call: (T) -> Void
    init(_ call: @escaping (T) -> Void) { self.call = call }
}

@MainActor
private final class Recognition {
    static let shared = Recognition()
    var model: Qwen3ASRModel?
    var busy = false
    private var loadedDirectory: String?
    private var loading: (directory: String, task: Task<Bool, Never>)?

    /// Idempotent: an already loaded model returns immediately, and a second request for the
    /// model being loaded waits for that load instead of failing.
    func prepare(_ directory: String) async -> Bool {
        if loadedDirectory == directory, model != nil { return true }
        if let loading, loading.directory == directory { return await loading.task.value }
        guard !busy else { return false }
        busy = true
        model = nil; loadedDirectory = nil
        let task = Task<Bool, Never> { @MainActor in
            do {
                self.model = try await Qwen3ASRModel.fromModelDirectory(URL(fileURLWithPath: directory))
                self.loadedDirectory = directory
                return true
            } catch { return false }
        }
        loading = (directory, task)
        let ready = await task.value
        loading = nil
        busy = false
        return ready
    }
    func transcribe(_ data: Data, context: String) -> String? {
        guard !busy, let model, context.utf8.count <= 4096, !data.isEmpty, data.count <= 60 * 16_000 * 4,
              data.count.isMultiple(of: 4) else { return nil }
        busy = true
        defer { busy = false }
        let samples = data.withUnsafeBytes { bytes in
            stride(from: 0, to: data.count, by: 4).map { bytes.loadUnaligned(fromByteOffset: $0, as: Float.self) }
        }
        guard samples.allSatisfy({ $0.isFinite && abs($0) <= 1 }) else { return nil }
        let result = model.generate(audio: MLXArray(samples), maxTokens: 1024, context: context, language: nil, chunkDuration: 30)
        return result.text
    }
}

private final class Service: NSObject, NSXPCListenerDelegate, VoiceWorkerProtocol {
    private let lock = NSLock()
    private var connections = 0
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(Identifiers.codeRequirement(for: Identifiers.appBundleID))
        connection.exportedInterface = NSXPCInterface(with: VoiceWorkerProtocol.self)
        connection.exportedObject = self
        lock.lock(); connections += 1; lock.unlock()
        // Exit (releasing model memory) only when the last client connection is gone; one stale
        // connection closing must not kill a load or transcription running on another.
        connection.invalidationHandler = { [weak self] in
            guard let self else { exit(0) }
            self.lock.lock(); self.connections -= 1; let remaining = self.connections; self.lock.unlock()
            if remaining <= 0 { exit(0) }
        }
        connection.resume()
        return true
    }
    func prepare(directory: String, reply: @escaping (Bool) -> Void) {
        let response = Reply(reply)
        Task { @MainActor in response.call(await Recognition.shared.prepare(directory)) }
    }
    func transcribe(audio: Data, context: String, reply: @escaping (String?) -> Void) {
        let response = Reply(reply)
        Task { @MainActor in response.call(Recognition.shared.transcribe(audio, context: context)) }
    }
    // Terminate even when the MLX thread is busy; cancellation must release model memory.
    func shutdown() { exit(0) }
}

if CommandLine.arguments.contains("--self-test") {
    guard (MLXArray([1, 2, 3]) + 1).sum().item(Int.self) == 9 else { exit(1) }
    print("RockType voice MLX self-test passed")
    exit(0)
}
private let service = Service()
let listener = NSXPCListener.service()
listener.delegate = service
listener.resume()
