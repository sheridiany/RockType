import Foundation
import RoarkTCore
import RoarkTXPCProtocol

/// One adapter per runner. Reconnect lazily after interruption; no polling or content cache.
@MainActor
public final class TextTranslationXPCClient: TextTranslationClient {
    public enum Failure: Error, Sendable { case unavailable, disconnected, timedOut, invalidReply }
    private struct Pending {
        let session: UUID
        let generation: UInt64
        let finish: (Result<String, Error>) -> Void
    }
    private let makeConnection: () -> NSXPCConnection
    private let timeout: Duration
    private var connection: NSXPCConnection?
    private var epoch = UUID()
    private var pending: [UUID: Pending] = [:]

    public init(timeout: Duration = .seconds(20), makeConnection: @escaping () -> NSXPCConnection = {
        let connection = NSXPCConnection(machServiceName: Identifiers.translationServiceName)
        connection.setCodeSigningRequirement(Identifiers.codeRequirement(for: Identifiers.translationServiceName))
        return connection
    }) {
        self.timeout = timeout; self.makeConnection = makeConnection
    }
    isolated deinit { connection?.invalidate() }
    public func start() {}
    public func stop() { disconnect(epoch) }

    public func translate(sessionID: UUID, generation: UInt64, text: String, target: String) async throws -> String {
        guard generation > 0, generation <= UInt64(Int64.max) else { throw Failure.invalidReply }
        let requestID = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let connection = ensureConnection()
                let currentEpoch = epoch
                let deadline = Task { [weak self] in
                    guard let timeout = self?.timeout else { return }
                    do { try await Task.sleep(for: timeout) } catch { return }
                    guard let self, self.pending[requestID] != nil else { return }
                    self.sendCancel(sessionID, generation)
                    self.resolve(requestID, .failure(Failure.timedOut))
                    self.disconnect(currentEpoch)
                }
                pending[requestID] = Pending(session: sessionID, generation: generation, finish: { result in
                    deadline.cancel(); continuation.resume(with: result)
                })
                guard let proxy = connection.remoteObjectProxyWithErrorHandler({ @Sendable [weak self] _ in
                    Task { @MainActor in
                        self?.resolve(requestID, .failure(Failure.disconnected))
                        self?.disconnect(currentEpoch)
                    }
                }) as? RoarkTTextTranslationXPCProtocol else {
                    resolve(requestID, .failure(Failure.unavailable)); disconnect(currentEpoch); return
                }
                proxy.translateText(sessionID: sessionID.uuidString, generation: Int64(generation), text: text,
                    target: target) { @Sendable [weak self] returnedGeneration, translated, error in
                        Task { @MainActor in
                            guard let self, self.epoch == currentEpoch else { return }
                            if let error {
                                let ns = error as NSError
                                let failure: Error = ns.domain == TranslationXPC.errorDomain && ns.code == 4
                                    ? CancellationError() : Failure.unavailable
                                self.resolve(requestID, .failure(failure))
                                if ns.domain == TranslationXPC.errorDomain && ns.code == 7 { self.disconnect(currentEpoch) }
                            } else if returnedGeneration == Int64(generation), let translated,
                                      !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                self.resolve(requestID, .success(translated))
                            } else { self.resolve(requestID, .failure(Failure.invalidReply)) }
                        }
                    }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                guard let self, self.pending[requestID] != nil else { return }
                self.sendCancel(sessionID, generation)
                self.resolve(requestID, .failure(CancellationError()))
            }
        }
    }

    public func cancel(sessionID: UUID, throughGeneration: UInt64) {
        sendCancel(sessionID, throughGeneration)
        for (id, request) in pending where request.session == sessionID && request.generation <= throughGeneration {
            resolve(id, .failure(CancellationError()))
        }
    }

    private func sendCancel(_ session: UUID, _ generation: UInt64) {
        guard generation > 0, generation <= UInt64(Int64.max), let connection,
              let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in }) as? RoarkTTextTranslationXPCProtocol else { return }
        proxy.cancelText(sessionID: session.uuidString, throughGeneration: Int64(generation))
    }
    private func resolve(_ id: UUID, _ result: Result<String, Error>) {
        pending.removeValue(forKey: id)?.finish(result)
    }
    private func ensureConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = makeConnection()
        connection.remoteObjectInterface = NSXPCInterface(with: RoarkTTextTranslationXPCProtocol.self)
        epoch = UUID()
        let current = epoch
        connection.interruptionHandler = { [weak self] in Task { @MainActor in self?.disconnect(current) } }
        connection.invalidationHandler = { [weak self] in Task { @MainActor in self?.disconnect(current) } }
        self.connection = connection; connection.resume()
        return connection
    }
    private func disconnect(_ current: UUID) {
        guard current == epoch else { return }
        let old = connection
        connection = nil; epoch = UUID()
        old?.interruptionHandler = nil; old?.invalidationHandler = nil; old?.invalidate()
        let requests = Array(pending.values)
        pending.removeAll()
        requests.forEach { $0.finish(.failure(Failure.disconnected)) }
    }
}
