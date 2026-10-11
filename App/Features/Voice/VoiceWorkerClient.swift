import Foundation
import RoarkTCore
import RoarkTPlatform

@MainActor final class VoiceWorkerClient: VoiceRecognizing {
    private var connection: NSXPCConnection?
    private var loaded: URL?
    func prepare(directory: URL) async throws {
        if loaded == directory, connection != nil { return }
        do { try await load(directory) }
        catch VoiceFailure.unavailable {
            // A worker that was just shut down may still be exiting; retry once on a fresh process.
            stop()
            try await Task.sleep(for: .milliseconds(400))
            try await load(directory)
        }
    }
    /// Reuses the live connection: replacing it would close the old one under an in-flight load.
    private func load(_ directory: URL) async throws {
        let connection: NSXPCConnection
        if let existing = self.connection {
            connection = existing
        } else {
            connection = NSXPCConnection(serviceName: Identifiers.voiceWorkerID)
            connection.setCodeSigningRequirement(Identifiers.codeRequirement(for: Identifiers.voiceWorkerID))
            connection.remoteObjectInterface = NSXPCInterface(with: VoiceWorkerProtocol.self)
            self.connection = connection
            connection.resume()
        }
        loaded = nil
        do {
            let gate = VoiceReply<Bool>()
            let ready = try await gate.wait(seconds: 90) { gate in
                let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable _ in
                    Task { @MainActor in gate.finish(.failure(VoiceFailure.unavailable)) }
                } as? VoiceWorkerProtocol
                guard let proxy else { gate.finish(.failure(VoiceFailure.unavailable)); return }
                proxy.prepare(directory: directory.path) { @Sendable ready in
                    Task { @MainActor in gate.finish(.success(ready)) }
                }
            }
            try Task.checkCancellation()
            guard self.connection === connection, ready else { throw VoiceFailure.model }
            loaded = directory
        } catch { if self.connection === connection { stop() }; throw error }
    }
    func transcribe(_ audio: Data) async throws -> String {
        try await recognize(audio, seconds: 240, allowsEmpty: false)
    }
    func preview(_ audio: Data) async throws -> String {
        try await recognize(audio, seconds: Double(VoiceAudioSegmentation.previewSeconds), allowsEmpty: true)
    }
    private func recognize(_ audio: Data, seconds: Double, allowsEmpty: Bool) async throws -> String {
        guard let connection, loaded != nil else { throw VoiceFailure.unavailable }
        guard SecureInput.status() == .allowed else { throw VoiceFailure.permission }
        let vocabulary = Task.detached(priority: .utility) { VoiceContextVocabulary.load() }
        let context = await withTaskCancellationHandler { await vocabulary.value } onCancel: { vocabulary.cancel() }
        try Task.checkCancellation()
        guard self.connection === connection, SecureInput.status() == .allowed else { throw VoiceFailure.permission }
        do {
            let gate = VoiceReply<String?>()
            let result = try await gate.wait(seconds: seconds) { gate in
                let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable _ in
                    Task { @MainActor in gate.finish(.failure(VoiceFailure.unavailable)) }
                } as? VoiceWorkerProtocol
                guard let proxy else { gate.finish(.failure(VoiceFailure.unavailable)); return }
                proxy.transcribe(audio: audio, context: context) { @Sendable text in Task { @MainActor in gate.finish(.success(text)) } }
            }
            try Task.checkCancellation()
            guard self.connection === connection, let result, allowsEmpty || !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VoiceFailure.empty
            }
            return result
        } catch { if self.connection === connection { stop() }; throw error }
    }
    func stop() {
        let old = connection
        connection = nil; loaded = nil
        (old?.remoteObjectProxyWithErrorHandler { @Sendable _ in } as? VoiceWorkerProtocol)?.shutdown()
        old?.invalidate()
    }
}
