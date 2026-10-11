import Foundation
import RoarkTCore
import RoarkTXPCProtocol

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
