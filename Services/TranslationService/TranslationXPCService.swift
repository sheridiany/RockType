import Foundation
import RoarkTCore
import RoarkTXPCProtocol
import Security

@MainActor
final class TranslationCoordinator {
    private struct SessionKey: Hashable {
        let connectionID: UUID
        let sessionID: String
    }

    private let backend: any DynamicTextTranslating
    private var latestGenerations: [SessionKey: Int64] = [:]
    private var tasks: [SessionKey: Task<Void, Never>] = [:]
    private var controllerInputGeneration: Int64 = 0
    let dictationEndpoints = DictationEndpointRegistry()
    let textTranslations: TextTranslationCoordinator

    init(backend: any DynamicTextTranslating = DynamicTranslatorFactory.make(),
         textBackend: any SelectionTextTranslating = SelectionTranslatorFactory.make()) {
        self.textTranslations = TextTranslationCoordinator(backend: textBackend)
        self.backend = backend
    }

    func translate(
        connectionID: UUID,
        sessionID: String,
        generation: Int64,
        request: CandidateTranslationRequest,
        withReply reply: @escaping @Sendable (Int64, String?, String?, String?, NSError?) -> Void
    ) {
        guard UUID(uuidString: sessionID) != nil, generation > 0 else {
            reply(generation, nil, nil, nil, Self.error(code: 1, description: "Invalid translation request."))
            return
        }

        let key = SessionKey(connectionID: connectionID, sessionID: sessionID)
        if let latest = latestGenerations[key], generation <= latest {
            reply(generation, nil, nil, nil, Self.error(code: 2, description: "Stale translation generation."))
            return
        }
        latestGenerations[key] = generation
        tasks.removeValue(forKey: key)?.cancel()

        tasks[key] = Task { [weak self, backend] in
            defer {
                if self?.latestGenerations[key] == generation { self?.tasks[key] = nil }
            }
            do {
                try await Task.sleep(for: .milliseconds(120))
                try Task.checkCancellation()
                let translated = try await backend.translate(request.sourceText, direction: request.direction)
                try Task.checkCancellation()
                guard let self, self.latestGenerations[key] == generation else {
                    reply(generation, nil, nil, nil, Self.error(code: 3, description: "Translation superseded."))
                    return
                }
                reply(generation, request.direction.rawValue, request.sourceText, translated, nil)
            } catch is CancellationError {
                reply(generation, nil, nil, nil, Self.error(code: 4, description: "Translation cancelled."))
            } catch {
                reply(generation, nil, nil, nil, CandidateTranslationFailure.from(error) as NSError)
            }
        }
    }

    func cancel(connectionID: UUID, sessionID: String, throughGeneration: Int64) {
        let key = SessionKey(connectionID: connectionID, sessionID: sessionID)
        guard UUID(uuidString: sessionID) != nil, throughGeneration > 0 else { return }
        let latest = latestGenerations[key] ?? 0
        guard latest <= throughGeneration else { return }
        // Keep a watermark even when cancellation arrives before the request.
        latestGenerations[key] = throughGeneration
        tasks.removeValue(forKey: key)?.cancel()
    }

    func removeConnection(_ connectionID: UUID) {
        dictationEndpoints.remove(owner: connectionID)
        textTranslations.removeConnection(connectionID)
        let keys = latestGenerations.keys.filter { $0.connectionID == connectionID }
        for key in keys {
            tasks.removeValue(forKey: key)?.cancel()
            latestGenerations[key] = nil
        }
    }

    func recordControllerInput() {
        controllerInputGeneration = controllerInputGeneration == Int64.max
            ? 1
            : controllerInputGeneration + 1
    }

    func currentControllerInputGeneration() -> Int64 {
        controllerInputGeneration
    }

    private static func error(code: Int, description: String) -> NSError {
        NSError(
            domain: TranslationXPC.errorDomain,
            code: code,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}

enum TranslationClientRole {
    case inputMethod
    case mainApp

    var identifier: String {
        switch self {
        case .inputMethod: Identifiers.inputMethodBundleID
        case .mainApp: Identifiers.appBundleID
        }
    }
}

final class TranslationXPCService: NSObject, RoarkTTextTranslationXPCProtocol {
    private final class Reply: @unchecked Sendable {
        private let block: (Int64, String?, String?, String?, Error?) -> Void

        init(_ block: @escaping (Int64, String?, String?, String?, Error?) -> Void) {
            self.block = block
        }

        func call(
            _ generation: Int64,
            _ direction: String?,
            _ sourceText: String?,
            _ translatedText: String?,
            _ error: NSError?
        ) {
            block(generation, direction, sourceText, translatedText, error)
        }
    }

    private final class GenerationReply: @unchecked Sendable {
        private let block: (Int64, Error?) -> Void

        init(_ block: @escaping (Int64, Error?) -> Void) {
            self.block = block
        }

        func call(_ generation: Int64, _ error: NSError?) {
            block(generation, error)
        }
    }

    let connectionID = UUID()
    let coordinator: TranslationCoordinator
    let role: TranslationClientRole
    private let rejectConnection: () -> Void

    init(coordinator: TranslationCoordinator, role: TranslationClientRole,
         rejectConnection: @escaping () -> Void = {}) {
        self.coordinator = coordinator
        self.role = role
        self.rejectConnection = rejectConnection
        super.init()
    }

    func translateCandidate(
        sessionID: String,
        generation: Int64,
        request: [String: String],
        withReply reply: @escaping (Int64, String?, String?, String?, Error?) -> Void
    ) {
        guard role == .inputMethod else {
            reply(generation, nil, nil, nil, Self.authorizationError())
            return
        }
        let candidate: CandidateTranslationRequest
        do {
            candidate = try CandidateTranslationRequest(payload: request)
        } catch {
            let unsupported = (error as? CandidateTranslationRequest.ValidationError) == .unsupportedVersion
            reply(generation, nil, nil, nil, NSError(
                domain: TranslationXPC.errorDomain, code: unsupported ? 6 : 1,
                userInfo: [NSLocalizedDescriptionKey: unsupported ? "候选翻译协议版本不兼容，请完成升级。" : "候选翻译请求无效。"]
            ))
            return
        }
        guard generation > 0 else {
            reply(generation, nil, nil, nil, NSError(domain: TranslationXPC.errorDomain, code: 1))
            return
        }
        let reply = Reply(reply)
        Task { @MainActor [connectionID, coordinator] in
            coordinator.translate(connectionID: connectionID, sessionID: sessionID,
                generation: generation, request: candidate, withReply: reply.call)
        }
    }

    func cancel(sessionID: String, throughGeneration: Int64) {
        guard role == .inputMethod else { return }
        Task { @MainActor [connectionID, coordinator] in
            coordinator.cancel(
                connectionID: connectionID,
                sessionID: sessionID,
                throughGeneration: throughGeneration
            )
        }
    }

    func recordControllerInput() {
        guard role == .inputMethod else { return }
        Task { @MainActor [coordinator] in
            coordinator.recordControllerInput()
        }
    }

    func controllerInputGeneration(reply: @escaping (Int64, Error?) -> Void) {
        guard role == .mainApp else {
            reply(0, Self.authorizationError())
            return
        }
        let reply = GenerationReply(reply)
        Task { @MainActor [coordinator] in
            reply.call(coordinator.currentControllerInputGeneration(), nil)
        }
    }

    func ping(reply: @escaping (String) -> Void) {
        guard role == .mainApp else { rejectConnection(); return }
        reply(CandidateTranslationRequest.version)
    }

    func invalidate() {
        Task { @MainActor [connectionID, coordinator] in
            coordinator.removeConnection(connectionID)
        }
    }
    private static func authorizationError() -> NSError {
        NSError(
            domain: TranslationXPC.errorDomain,
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "The XPC operation is not allowed for this client."]
        )
    }
}

final class TranslationXPCListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    typealias ConnectionValidator = (NSXPCConnection) -> TranslationClientRole?

    private let coordinator: TranslationCoordinator
    private let clientRole: ConnectionValidator
    private let idleExitDelay: TimeInterval
    private let lock = NSLock()
    private var connectionCount = 0
    private var idleGeneration: UUID?

    init(
        coordinator: TranslationCoordinator = MainActor.assumeIsolated { TranslationCoordinator() },
        clientRole: @escaping ConnectionValidator = TranslationClientCodeValidator.role,
        idleExitDelay: TimeInterval = ProcessInfo.processInfo.environment[
            "ROARKT_TRANSLATION_IDLE_TIMEOUT"
        ].flatMap(TimeInterval.init) ?? 30
    ) {
        self.coordinator = coordinator
        self.clientRole = clientRole
        self.idleExitDelay = idleExitDelay
        super.init()
        scheduleIdleExit()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let role = clientRole(connection) else { return false }

        // Pin every message to the exact role checked with SecCode, avoiding PID reuse
        // between validation and delivery. Available on our macOS 14 baseline.
        connection.setCodeSigningRequirement(Identifiers.codeRequirement(for: role.identifier))
        let service = TranslationXPCService(coordinator: coordinator, role: role,
            rejectConnection: { [weak connection] in connection?.invalidate() })
        connection.exportedInterface = NSXPCInterface(with: RoarkTTextTranslationXPCProtocol.self)
        connection.exportedObject = service
        connection.invalidationHandler = { [weak self, service] in
            service.invalidate()
            self?.connectionClosed()
        }
        connectionInterruptedOrOpened()
        connection.resume()
        return true
    }

    private func connectionInterruptedOrOpened() {
        lock.lock()
        connectionCount += 1
        idleGeneration = nil
        lock.unlock()
    }

    private func connectionClosed() {
        lock.lock()
        connectionCount = max(0, connectionCount - 1)
        guard connectionCount == 0 else {
            lock.unlock()
            return
        }
        let generation = UUID()
        idleGeneration = generation
        lock.unlock()
        scheduleIdleExit(generation: generation)
    }

    private func scheduleIdleExit() {
        lock.lock()
        let generation = UUID()
        idleGeneration = generation
        lock.unlock()
        scheduleIdleExit(generation: generation)
    }

    private func scheduleIdleExit(generation: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + idleExitDelay) { [weak self] in
            self?.exitIfIdle(generation: generation)
        }
    }

    private func exitIfIdle(generation: UUID) {
        lock.lock()
        let shouldExit = connectionCount == 0 && idleGeneration == generation
        lock.unlock()
        if shouldExit {
            Foundation.exit(EXIT_SUCCESS)
        }
    }
}

enum TranslationClientCodeValidator {
    static func role(for connection: NSXPCConnection) -> TranslationClientRole? {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: connection.processIdentifier)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else { return nil }
        return role(for: code)
    }

    static func role(for code: SecCode) -> TranslationClientRole? {
        for role in [TranslationClientRole.inputMethod, .mainApp] {
            var requirement: SecRequirement?
            let text = Identifiers.codeRequirement(for: role.identifier)
            guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
                  let requirement else { continue }
            if SecCodeCheckValidity(code, [], requirement) == errSecSuccess { return role }
        }
        return nil
    }
}
