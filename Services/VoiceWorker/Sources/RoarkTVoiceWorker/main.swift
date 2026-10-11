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

    func prepare(_ directory: String) async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        model = nil
        do {
            model = try await Qwen3ASRModel.fromModelDirectory(URL(fileURLWithPath: directory))
            return true
        } catch { return false }
    }
    func transcribe(_ data: Data) -> String? {
        guard !busy, let model, !data.isEmpty, data.count <= 60 * 16_000 * 4,
              data.count.isMultiple(of: 4) else { return nil }
        busy = true
        defer { busy = false }
        let samples = data.withUnsafeBytes { bytes in
            stride(from: 0, to: data.count, by: 4).map { bytes.loadUnaligned(fromByteOffset: $0, as: Float.self) }
        }
        guard samples.allSatisfy({ $0.isFinite && abs($0) <= 1 }) else { return nil }
        let result = model.generate(audio: MLXArray(samples), maxTokens: 1024, language: nil, chunkDuration: 30)
        return result.text
    }
}

private final class Service: NSObject, NSXPCListenerDelegate, VoiceWorkerProtocol {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(Identifiers.codeRequirement(for: Identifiers.appBundleID))
        connection.exportedInterface = NSXPCInterface(with: VoiceWorkerProtocol.self)
        connection.exportedObject = self
        connection.invalidationHandler = { exit(0) }
        connection.resume()
        return true
    }
    func prepare(directory: String, reply: @escaping (Bool) -> Void) {
        let response = Reply(reply)
        Task { @MainActor in response.call(await Recognition.shared.prepare(directory)) }
    }
    func transcribe(audio: Data, reply: @escaping (String?) -> Void) {
        let response = Reply(reply)
        Task { @MainActor in response.call(Recognition.shared.transcribe(audio)) }
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
