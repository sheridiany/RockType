import Foundation
import RoarkTCore
import RoarkTXPCProtocol

/// Main-app-only discovery and input verification calls. No text crosses this interface.
@MainActor
final class TranslationServiceClient {
    struct InputGeneration: Sendable, Equatable {
        let connectionID: UUID
        let value: Int64
    }

    enum Failure: Error { case unavailable, disconnected, timedOut }
    private var connection: NSXPCConnection?
    private var connectionID = UUID()
    private var pending: [UUID: (Error) -> Void] = [:]
    private let makeConnection: () -> NSXPCConnection

    init(makeConnection: @escaping () -> NSXPCConnection = {
        let connection = NSXPCConnection(machServiceName: Identifiers.translationServiceName)
        connection.setCodeSigningRequirement(Identifiers.codeRequirement(for: Identifiers.translationServiceName))
        return connection
    }) {
        self.makeConnection = makeConnection
    }

    isolated deinit { connection?.invalidate() }

    func ping() async throws -> String {
        try await request { proxy, reply in proxy.ping { @Sendable in reply(.success($0)) } }
    }

    func controllerInputGeneration() async throws -> InputGeneration {
        _ = ensureConnection()
        let id = connectionID
        let value: Int64 = try await request { proxy, reply in
            proxy.controllerInputGeneration { @Sendable value, error in
                if let error { reply(.failure(error)) } else { reply(.success(value)) }
            }
        }
        guard id == connectionID else { throw Failure.disconnected }
        return InputGeneration(connectionID: id, value: value)
    }

    func dictationEndpoint() async throws -> NSXPCListenerEndpoint? {
        try await request { proxy, reply in proxy.dictationEndpoint { @Sendable in reply(.success($0)) } }
    }

    func invalidate() {
        disconnect(connectionID)
    }

    private func ensureConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = makeConnection()
        connection.remoteObjectInterface = NSXPCInterface(with: RoarkTTranslationXPCProtocol.self)
        connectionID = UUID()
        let id = connectionID
        connection.interruptionHandler = { @Sendable [weak self] in
            Task { @MainActor in self?.disconnect(id) }
        }
        connection.invalidationHandler = { @Sendable [weak self] in
            Task { @MainActor in self?.disconnect(id) }
        }
        self.connection = connection
        connection.resume()
        return connection
    }

    // Rebuild lazily on the next call, without a reconnect loop while the service is absent.
    private func disconnect(_ id: UUID) {
        guard id == connectionID else { return }
        let old = connection
        connection = nil
        connectionID = UUID()
        old?.interruptionHandler = nil
        old?.invalidationHandler = nil
        old?.invalidate()
        let failures = Array(pending.values)
        pending.removeAll()
        failures.forEach { $0(Failure.disconnected) }
    }

    private func request<Value: Sendable>(
        _ invoke: (RoarkTTranslationXPCProtocol, @escaping @Sendable (Result<Value, Error>) -> Void) -> Void
    ) async throws -> Value {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let connection = ensureConnection()
                let epoch = connectionID
                let timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(4)) } catch { return }
                    guard self?.pending[id] != nil else { return }
                    self?.pending.removeValue(forKey: id)?(Failure.timedOut)
                    self?.disconnect(epoch)
                }
                pending[id] = { error in
                    timeout.cancel()
                    continuation.resume(throwing: error)
                }
                let reply: @Sendable (Result<Value, Error>) -> Void = { [weak self] result in
                    Task { @MainActor in
                        guard self?.pending.removeValue(forKey: id) != nil else { return }
                        timeout.cancel()
                        continuation.resume(with: result)
                    }
                }
                guard let proxy = connection.remoteObjectProxyWithErrorHandler({ @Sendable [weak self] error in
                    reply(.failure(error))
                    Task { @MainActor in self?.disconnect(epoch) }
                }) as? RoarkTTranslationXPCProtocol else {
                    pending.removeValue(forKey: id)?(Failure.unavailable)
                    disconnect(epoch)
                    return
                }
                invoke(proxy, reply)
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.pending.removeValue(forKey: id)?(CancellationError()) }
        }
    }
}
