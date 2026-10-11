import Foundation
import Testing
import RoarkTCore
import RoarkTXPCProtocol
@testable import RoarkTTranslationService
@testable import RoarkTApp

private func aiConfig(timeout: String = "1") -> [String: String] {
    ["baseURL": "https://example.invalid/v1", "model": "synthetic-model", "apiKey": "synthetic-test-key",
     "timeout": timeout, "rewritePrompt": "Synthetic rewrite", "polishPrompt": "Synthetic polish",
     "translatePrompt": "Synthetic translate {{target}}"]
}
private struct AIResponse: Sendable {
    let generation: Int64
    let source: String?
    let result: String?
    let code: Int?
    init(_ generation: Int64, _ source: String?, _ result: String?, _ error: NSError?) {
        self.generation = generation; self.source = source; self.result = result; code = error?.code
    }
}
@MainActor private func aiPerform(_ coordinator: InputAICoordinator, connection: UUID = UUID(),
                                 session: String = UUID().uuidString, generation: Int64 = 1,
                                 text: String = "Synthetic source", action: String = "rewrite") async -> AIResponse {
    await withCheckedContinuation { continuation in
        coordinator.rewrite(connectionID: connection, sessionID: session, generation: generation, text: text, action: action) {
            continuation.resume(returning: AIResponse($0, $1, $2, $3))
        }
    }
}
private actor HeldAI {
    var pending: [CheckedContinuation<String, Never>] = []
    var calls = 0
    func run() async -> String {
        calls += 1
        return await withCheckedContinuation { pending.append($0) }
    }
    func release() { let old = pending; pending = []; old.forEach { $0.resume(returning: "Synthetic late result") } }
}

@Test @MainActor func inputAIRequiresValidConfigurationAndOwnerLifetime() async {
    let coordinator = InputAICoordinator(isSecure: { false }, complete: { _, prompt in prompt })
    let owner = UUID()
    #expect(await aiPerform(coordinator).code == 101)
    #expect(coordinator.configure(aiConfig(), owner: owner) == nil)
    #expect(await aiPerform(coordinator, action: "translate").result == "Synthetic translate zh-Hans\n\nSynthetic source")
    #expect(await aiPerform(coordinator, action: "polish").result == "Synthetic polish\n\nSynthetic source")
    coordinator.removeConnection(UUID())
    #expect(await aiPerform(coordinator).code == nil)
    coordinator.removeConnection(owner)
    #expect(await aiPerform(coordinator).code == 101)
    #expect(coordinator.configure(aiConfig(), owner: owner) == nil)
    #expect(coordinator.configure([:], owner: owner) == nil)
    #expect(await aiPerform(coordinator).code == 101)
    #expect(coordinator.configure(aiConfig(), owner: owner) == nil)
    #expect(coordinator.configure(["apiKey": "synthetic"], owner: owner)?.code == 100)
    #expect(await aiPerform(coordinator).code == 101)
}

@Test @MainActor func inputAIValidatesAndDeniesSecureInputWithoutCallingBackend() async {
    let coordinator = InputAICoordinator(isSecure: { true }, complete: { _, _ in
        Issue.record("Protected or invalid request reached transport"); return "Synthetic"
    })
    #expect(coordinator.configure(aiConfig(), owner: UUID()) == nil)
    #expect(await aiPerform(coordinator).code == 105)
    #expect(await aiPerform(coordinator, action: "unknown").code == 100)
    #expect(await aiPerform(coordinator, text: " ").code == 100)
    #expect(await aiPerform(coordinator, text: String(repeating: "x", count: 131_073)).code == 100)
    #expect(await aiPerform(coordinator, session: "bad").code == 100)
    #expect(await aiPerform(coordinator, generation: 0).code == 100)
    for timeout in ["nan", "0", "121"] { #expect(coordinator.configure(aiConfig(timeout: timeout), owner: UUID())?.code == 100) }
}

@Test @MainActor func inputAISupersessionCancellationAndDeadlineFinishWithoutBackendCooperation() async {
    let held = HeldAI()
    let coordinator = InputAICoordinator(isSecure: { false }, complete: { _, _ in await held.run() })
    let connection = UUID(), session = UUID().uuidString
    #expect(coordinator.configure(aiConfig(timeout: "0.2"), owner: UUID()) == nil)
    let first = Task { await aiPerform(coordinator, connection: connection, session: session) }
    while await held.calls < 1 { await Task.yield() }
    let second = Task { await aiPerform(coordinator, connection: connection, session: session, generation: 2) }
    #expect(await first.value.code == 103)
    while await held.calls < 2 { await Task.yield() }
    coordinator.cancel(connectionID: connection, sessionID: session, throughGeneration: 2)
    #expect(await second.value.code == 103)
    #expect(await aiPerform(coordinator, connection: connection, session: session, generation: 2).code == 102)
    #expect(await aiPerform(coordinator).code == 106)
    await held.release()
    coordinator.cancel(connectionID: connection, sessionID: session, throughGeneration: 9)
    #expect(await aiPerform(coordinator, connection: connection, session: session, generation: 8).code == 102)
}

@Test @MainActor func inputAIRevokesPendingOnClearDisconnectAndSecureInput() async {
    let held = HeldAI()
    var secure = false
    let coordinator = InputAICoordinator(isSecure: { secure }, complete: { _, _ in await held.run() })
    let owner = UUID()
    for step in 0..<3 {
        #expect(coordinator.configure(aiConfig(), owner: owner) == nil)
        let result = Task { await aiPerform(coordinator) }
        while await held.calls < step + 1 { await Task.yield() }
        switch step {
        case 0: #expect(coordinator.configure([:], owner: owner) == nil)
        case 1: coordinator.removeConnection(owner)
        default: secure = true
        }
        #expect(await result.value.code == (step == 2 ? 105 : 103))
        await held.release()
    }
}

@Test @MainActor func inputAIErrorMappingDoesNotExposeTransportErrors() async {
    let errors: [(AIClientError, Int)] = [(.timeout, 106), (.unauthorized, 107), (.modelNotFound, 108),
        (.rateLimited, 109), (.network, 110), (.decoding, 111), (.cancelled, 103)]
    for (error, code) in errors {
        let coordinator = InputAICoordinator(isSecure: { false }, complete: { _, _ in throw error })
        #expect(coordinator.configure(aiConfig(), owner: UUID()) == nil)
        #expect(await aiPerform(coordinator).code == code)
    }
    let coordinator = InputAICoordinator(isSecure: { false }, complete: { _, _ in
        throw NSError(domain: "synthetic-sensitive-provider-body", code: 9, userInfo: [NSLocalizedDescriptionKey: "synthetic-secret"])
    })
    #expect(coordinator.configure(aiConfig(), owner: UUID()) == nil)
    let error: NSError? = await withCheckedContinuation { continuation in
        coordinator.rewrite(connectionID: UUID(), sessionID: UUID().uuidString, generation: 1, text: "Synthetic", action: "rewrite") {
            continuation.resume(returning: $3)
        }
    }
    #expect(error?.code == 110)
    #expect(error?.localizedDescription.contains("synthetic") == false)
}

@Test @MainActor func inputAIRoleAuthorizationAndSharedCandidateGeneration() async {
    let ai = InputAICoordinator(isSecure: { false }, complete: { _, _ in "Synthetic result" })
    let coordinator = TranslationCoordinator(inputAI: ai)
    let ime = TranslationXPCService(coordinator: coordinator, role: .inputMethod)
    let app = TranslationXPCService(coordinator: coordinator, role: .mainApp)
    let rejected: Int? = await withCheckedContinuation { continuation in
        ime.configureAI(config: aiConfig()) { continuation.resume(returning: ($0 as NSError?)?.code) }
    }
    #expect(rejected == 104)
    let forbidden = await withCheckedContinuation { continuation in
        app.rewriteCandidate(sessionID: UUID().uuidString, generation: 1, text: "Synthetic", action: "rewrite") {
            continuation.resume(returning: AIResponse($0, $1, $2, $3 as NSError?))
        }
    }
    #expect(forbidden.code == 104)
    let configured: Int? = await withCheckedContinuation { continuation in
        app.configureAI(config: aiConfig()) { continuation.resume(returning: ($0 as NSError?)?.code) }
    }
    #expect(configured == nil)
    let session = UUID().uuidString
    coordinator.cancel(connectionID: ime.connectionID, sessionID: session, throughGeneration: 5)
    let stale = await withCheckedContinuation { continuation in
        ime.rewriteCandidate(sessionID: session, generation: 4, text: "Synthetic", action: "rewrite") {
            continuation.resume(returning: AIResponse($0, $1, $2, $3 as NSError?))
        }
    }
    #expect(stale.code == 102)
    let current = await withCheckedContinuation { continuation in
        ime.rewriteCandidate(sessionID: session, generation: 6, text: "Synthetic", action: "rewrite") {
            continuation.resume(returning: AIResponse($0, $1, $2, $3 as NSError?))
        }
    }
    #expect(current.generation == 6 && current.source == "Synthetic" && current.result == "Synthetic result")
    _ = NSXPCInterface(with: RoarkTInputAIXPCProtocol.self)
}

private final class AIListener: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let service: TranslationXPCService
    private let lock = NSLock()
    private var connections: [NSXPCConnection] = []
    init(_ service: TranslationXPCService) { self.service = service }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: RoarkTInputAIXPCProtocol.self)
        connection.exportedObject = service
        lock.lock(); connections.append(connection); lock.unlock()
        connection.resume(); return true
    }
    func stop() {
        lock.lock(); let old = connections; connections = []; lock.unlock()
        old.forEach { $0.invalidate() }
    }
}

@Test @MainActor func inputAIRealXPCDictionaryAndReplyRoundTrip() async throws {
    let coordinator = TranslationCoordinator(inputAI: InputAICoordinator(isSecure: { false }, complete: { _, _ in "Synthetic result" }))
    let appDelegate = AIListener(TranslationXPCService(coordinator: coordinator, role: .mainApp))
    let imeDelegate = AIListener(TranslationXPCService(coordinator: coordinator, role: .inputMethod))
    let appListener = NSXPCListener.anonymous(), imeListener = NSXPCListener.anonymous()
    appListener.delegate = appDelegate; imeListener.delegate = imeDelegate
    appListener.resume(); imeListener.resume()
    let app = NSXPCConnection(listenerEndpoint: appListener.endpoint)
    let ime = NSXPCConnection(listenerEndpoint: imeListener.endpoint)
    app.remoteObjectInterface = NSXPCInterface(with: RoarkTInputAIXPCProtocol.self)
    ime.remoteObjectInterface = NSXPCInterface(with: RoarkTInputAIXPCProtocol.self)
    app.resume(); ime.resume()
    defer { app.invalidate(); ime.invalidate(); appDelegate.stop(); imeDelegate.stop(); appListener.invalidate(); imeListener.invalidate() }
    let appProxy = try #require(app.remoteObjectProxy as? RoarkTInputAIXPCProtocol)
    let imeProxy = try #require(ime.remoteObjectProxy as? RoarkTInputAIXPCProtocol)
    let code: Int? = await withCheckedContinuation { continuation in
        appProxy.configureAI(config: aiConfig()) { continuation.resume(returning: ($0 as NSError?)?.code) }
    }
    #expect(code == nil)
    let response = await withCheckedContinuation { continuation in
        imeProxy.rewriteCandidate(sessionID: UUID().uuidString, generation: 1, text: "Synthetic source", action: "polish") {
            continuation.resume(returning: AIResponse($0, $1, $2, $3 as NSError?))
        }
    }
    #expect(response.source == "Synthetic source" && response.result == "Synthetic result")
}

@Test @MainActor func inputAIAppClientPublishesAndRevokesOverAnonymousXPC() async throws {
    let ai = InputAICoordinator(isSecure: { false }, complete: { _, _ in "Synthetic result" })
    let service = TranslationXPCService(coordinator: TranslationCoordinator(inputAI: ai), role: .mainApp)
    let delegate = AIListener(service)
    let listener = NSXPCListener.anonymous(); listener.delegate = delegate; listener.resume()
    defer { delegate.stop(); listener.invalidate() }
    var count = 0
    let client = InputAIConfigurationClient(makeConnection: {
        count += 1; return NSXPCConnection(listenerEndpoint: listener.endpoint)
    })
    try await client.configure(aiConfig())
    #expect(await aiPerform(ai).result == "Synthetic result")
    try await client.configure([:])
    #expect(await aiPerform(ai).code == 101)
    try await client.configure(aiConfig())
    client.clearAndInvalidate()
    var cleared = false
    let deadline = ContinuousClock.now + .seconds(3)
    while !cleared, ContinuousClock.now < deadline {
        cleared = await aiPerform(ai).code == 101
        await Task.yield()
    }
    #expect(cleared)
    try await client.configure(aiConfig())
    #expect(count == 2)
    #expect(await aiPerform(ai).result == "Synthetic result")
    client.invalidate()
}

@Test @MainActor func inputAIOldOwnerCannotRevokeNewConnectionConfiguration() async {
    let ai = InputAICoordinator(isSecure: { false }, complete: { _, _ in "Synthetic result" })
    let old = UUID(), current = UUID()
    #expect(ai.configure(aiConfig(), owner: old) == nil)
    #expect(ai.configure(aiConfig(), owner: current) == nil)
    #expect(ai.configure([:], owner: old) == nil)
    ai.removeConnection(old)
    #expect(await aiPerform(ai).result == "Synthetic result")
    #expect(ai.configure([:], owner: current) == nil)
    #expect(await aiPerform(ai).code == 101)
}

@Test @MainActor func inputAIEndpointPolicyMatchesSharedAIClient() async {
    let ai = InputAICoordinator(isSecure: { false }, complete: { _, _ in "Synthetic" })
    for baseURL in ["http://127.0.0.1:8080/v1", "http://[::1]:8080/v1", "http://localhost/v1", "https://example.invalid/v1"] {
        var config = aiConfig(); config["baseURL"] = baseURL
        #expect(ai.configure(config, owner: UUID()) == nil)
        #expect(await aiPerform(ai).result == "Synthetic")
    }
    for baseURL in ["http://example.invalid", "http://127.0.0.2", "http://localhost.example.invalid", "https://user:pass@example.invalid", "https://example.invalid?key=synthetic"] {
        var config = aiConfig(); config["baseURL"] = baseURL
        #expect(ai.configure(config, owner: UUID())?.code == 100)
        #expect(await aiPerform(ai).code == 101)
    }
}
