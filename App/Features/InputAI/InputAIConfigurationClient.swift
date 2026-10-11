import Foundation
import RoarkTCore
import RoarkTXPCProtocol

@MainActor protocol InputAIConfiguring: AnyObject {
    var onDisconnect: (() -> Void)? { get set }
    func configure(_ config: [String: String]) async throws
    func invalidate()
    func clearAndInvalidate()
}

/// Owns a dedicated, authenticated connection: disconnect revokes its configuration.
@MainActor final class InputAIConfigurationClient: InputAIConfiguring {
    enum Failure: Error { case disconnected, timeout, rejected }
    var onDisconnect: (() -> Void)?
    private var connection: NSXPCConnection?
    private var epoch = UUID()
    private var pending: [UUID: (Error?) -> Void] = [:]
    private let timeout: Duration
    private let makeConnection: () -> NSXPCConnection

    init(timeout: Duration = .seconds(4), makeConnection: @escaping () -> NSXPCConnection = {
        let connection = NSXPCConnection(machServiceName: Identifiers.translationServiceName)
        connection.setCodeSigningRequirement(Identifiers.codeRequirement(for: Identifiers.translationServiceName))
        return connection
    }) { self.timeout = timeout; self.makeConnection = makeConnection }

    func configure(_ config: [String: String]) async throws {
        let request = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let connection = ensureConnection(), current = epoch
                let deadline = Task { [weak self, timeout] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    guard let self, self.pending[request] != nil else { return }
                    self.pending.removeValue(forKey: request)?(Failure.timeout)
                    self.disconnect(current)
                }
                pending[request] = { error in
                    deadline.cancel()
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
                guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] _ in
                    Task { @MainActor in self?.disconnect(current) }
                }) as? RoarkTInputAIXPCProtocol else {
                    disconnect(current); return
                }
                proxy.configureAI(config: config) { [weak self] error in
                    // Only the success bit crosses back into app state; never log NSError content.
                    let failed = error != nil
                    Task { @MainActor in
                        self?.pending.removeValue(forKey: request)?(failed ? Failure.rejected : nil)
                    }
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                guard let self, let finish = self.pending.removeValue(forKey: request) else { return }
                finish(CancellationError()); self.invalidate()
            }
        }
    }

    private func ensureConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = makeConnection(), current = UUID()
        epoch = current; self.connection = connection
        connection.remoteObjectInterface = NSXPCInterface(with: RoarkTInputAIXPCProtocol.self)
        connection.interruptionHandler = { [weak self] in Task { @MainActor in self?.disconnect(current) } }
        connection.invalidationHandler = { [weak self] in Task { @MainActor in self?.disconnect(current) } }
        connection.resume(); return connection
    }

    private func disconnect(_ current: UUID) {
        guard current == epoch else { return }
        invalidate(); onDisconnect?()
    }

    func invalidate() {
        let old = connection; connection = nil; epoch = UUID()
        old?.interruptionHandler = nil; old?.invalidationHandler = nil; old?.invalidate()
        let callbacks = Array(pending.values); pending.removeAll()
        callbacks.forEach { $0(Failure.disconnected) }
    }

    private final class ClosingConnection: @unchecked Sendable {
        let value: NSXPCConnection
        init(_ value: NSXPCConnection) { self.value = value }
        // NSXPCConnection.invalidate is safe from a reply handler or the main actor.
        func invalidate() { value.invalidate() }
    }

    func clearAndInvalidate() {
        guard let old = connection else { return }
        connection = nil; epoch = UUID()
        old.interruptionHandler = nil; old.invalidationHandler = nil
        let callbacks = Array(pending.values); pending.removeAll()
        callbacks.forEach { $0(CancellationError()) }
        // Send the explicit revocation before closing. Owner disconnect remains the
        // safety net if the app exits before this acknowledgement or deadline runs.
        let closing = ClosingConnection(old)
        if let proxy = old.remoteObjectProxyWithErrorHandler({ _ in closing.invalidate() }) as? RoarkTInputAIXPCProtocol {
            proxy.configureAI(config: [:]) { _ in closing.invalidate() }
            Task { [timeout] in try? await Task.sleep(for: timeout); closing.invalidate() }
        } else { old.invalidate() }
    }

    isolated deinit { connection?.invalidate() }
}
