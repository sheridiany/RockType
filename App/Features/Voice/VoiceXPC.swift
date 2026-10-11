import Foundation
import RoarkTCore
import RoarkTXPCProtocol

@MainActor
private final class VoiceReply<Value: Sendable> {
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

enum VoiceFailure: Error { case timeout, unavailable, model, empty, permission }

@MainActor protocol VoiceRecognizing: AnyObject {
    func prepare(directory: URL) async throws
    func transcribe(_ audio: Data) async throws -> String
    func stop()
}

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
        guard let connection, loaded != nil else { throw VoiceFailure.unavailable }
        do {
            let gate = VoiceReply<String?>()
            let result = try await gate.wait(seconds: 90) { gate in
                let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable _ in
                    Task { @MainActor in gate.finish(.failure(VoiceFailure.unavailable)) }
                } as? VoiceWorkerProtocol
                guard let proxy else { gate.finish(.failure(VoiceFailure.unavailable)); return }
                proxy.transcribe(audio: audio) { @Sendable text in Task { @MainActor in gate.finish(.success(text)) } }
            }
            try Task.checkCancellation()
            guard self.connection === connection, let result, !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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

struct VoiceTarget: Sendable {
    let token: String
    let applicationID: String
    let deadline: TimeInterval
}
@MainActor protocol VoiceCommitting: AnyObject {
    func capture(pid: Int32) async throws -> VoiceTarget
    func commit(_ text: String, target: VoiceTarget) async throws -> Bool
    func cancel(_ target: VoiceTarget?)
}
private struct VoiceEndpoint: @unchecked Sendable { let value: NSXPCListenerEndpoint? }

@MainActor final class VoiceCommitBridge: VoiceCommitting {
    private var connection: NSXPCConnection?
    func capture(pid: Int32) async throws -> VoiceTarget {
        cancel(nil)
        let registry = NSXPCConnection(machServiceName: Identifiers.translationServiceName)
        registry.setCodeSigningRequirement(Identifiers.codeRequirement(for: Identifiers.translationServiceName))
        registry.remoteObjectInterface = NSXPCInterface(with: RoarkTTranslationXPCProtocol.self)
        registry.resume()
        defer { registry.invalidate() }
        let gate = VoiceReply<VoiceEndpoint>()
        let endpoint = try await gate.wait(seconds: 3) { gate in
            let proxy = registry.remoteObjectProxyWithErrorHandler { @Sendable _ in
                Task { @MainActor in gate.finish(.failure(VoiceFailure.unavailable)) }
            } as? RoarkTTranslationXPCProtocol
            guard let proxy else { gate.finish(.failure(VoiceFailure.unavailable)); return }
            proxy.dictationEndpoint { @Sendable endpoint in
                let value = VoiceEndpoint(value: endpoint)
                Task { @MainActor in gate.finish(.success(value)) }
            }
        }
        try Task.checkCancellation()
        guard let endpoint = endpoint.value else { throw VoiceFailure.unavailable }
        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        connection.setCodeSigningRequirement(Identifiers.codeRequirement(for: Identifiers.inputMethodBundleID))
        connection.remoteObjectInterface = NSXPCInterface(with: RoarkTDictationXPCProtocol.self)
        self.connection = connection
        connection.resume()
        let capture = VoiceReply<VoiceTarget?>()
        do {
            let target = try await capture.wait(seconds: 3) { gate in
                let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable _ in
                    Task { @MainActor in gate.finish(.failure(VoiceFailure.unavailable)) }
                } as? RoarkTDictationXPCProtocol
                guard let proxy else { gate.finish(.failure(VoiceFailure.unavailable)); return }
                proxy.capture(applicationPID: pid) { @Sendable token, app in
                    let value = token.flatMap { token in app.map {
                        VoiceTarget(token: token, applicationID: $0, deadline: ProcessInfo.processInfo.systemUptime + 110)
                    } }
                    Task { @MainActor in gate.finish(.success(value)) }
                }
            }
            try Task.checkCancellation()
            guard self.connection === connection, let target else { throw VoiceFailure.unavailable }
            return target
        } catch { connection.invalidate(); if self.connection === connection { self.connection = nil }; throw error }
    }
    func commit(_ text: String, target: VoiceTarget) async throws -> Bool {
        guard let connection else { return false }
        let gate = VoiceReply<Bool>()
        return try await gate.wait(seconds: 3) { gate in
            let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable _ in
                Task { @MainActor in gate.finish(.failure(VoiceFailure.unavailable)) }
            } as? RoarkTDictationXPCProtocol
            guard let proxy else { gate.finish(.failure(VoiceFailure.unavailable)); return }
            proxy.commit(ticket: target.token, text: text, deadline: target.deadline) { @Sendable accepted in
                Task { @MainActor in gate.finish(.success(accepted)) }
            }
        }
    }
    func cancel(_ target: VoiceTarget?) {
        if let target { (connection?.remoteObjectProxyWithErrorHandler { @Sendable _ in } as? RoarkTDictationXPCProtocol)?.cancel(ticket: target.token) }
        connection?.invalidate(); connection = nil
    }
}
