import Foundation
import Testing
import RoarkTCore
import RoarkTXPCProtocol

@MainActor private final class TextBackend: SelectionTextTranslating {
    var calls = 0
    var target: String?
    var held: CheckedContinuation<String, Never>?
    func translate(_ text: String, target: String) async throws -> String {
        calls += 1; self.target = target
        if text == "slow" { return await withCheckedContinuation { held = $0 } }
        return "Synthetic translation"
    }
    func release() { held?.resume(returning: "Synthetic late translation"); held = nil }
}
private struct Response: Sendable {
    let generation: Int64
    let text: String?
    let code: Int?
    init(_ generation: Int64, _ text: String?, _ error: NSError?) {
        self.generation = generation; self.text = text; self.code = error?.code
    }
}
@MainActor private func perform(_ coordinator: TextTranslationCoordinator, connection: UUID = UUID(),
                               session: String = UUID().uuidString, generation: Int64 = 1,
                               text: String = "Synthetic source", target: String = "fr") async -> Response {
    await withCheckedContinuation { continuation in
        coordinator.translate(connectionID: connection, sessionID: session, generation: generation,
            text: text, target: target) { continuation.resume(returning: Response($0, $1, $2)) }
    }
}

@Test @MainActor func textValidationAndTargetDoNotConsumeInvalidGeneration() async {
    let backend = TextBackend()
    let coordinator = TextTranslationCoordinator(backend: backend)
    let connection = UUID(); let session = UUID().uuidString
    #expect(await perform(coordinator, session: "bad").code == 1)
    #expect(await perform(coordinator, generation: 0).code == 1)
    #expect(await perform(coordinator, text: " \n").code == 1)
    #expect(await perform(coordinator, text: String(repeating: "x", count: 131_073)).code == 1)
    #expect(await perform(coordinator, connection: connection, session: session, target: "bad/target").code == 1)
    #expect(backend.calls == 0)
    #expect(await perform(coordinator, connection: connection, session: session).text == "Synthetic translation")
    #expect(backend.target == "fr")
    #expect(await perform(coordinator, target: "auto").code == nil)
    #expect(backend.target == "zh-Hans")
}

@Test @MainActor func cancellationWatermarkAndConnectionIsolation() async {
    let backend = TextBackend()
    let coordinator = TextTranslationCoordinator(backend: backend)
    let first = UUID(); let second = UUID(); let session = UUID().uuidString
    coordinator.cancel(connectionID: first, sessionID: session, throughGeneration: 2)
    #expect(await perform(coordinator, connection: first, session: session, generation: 2).code == 2)
    #expect(await perform(coordinator, connection: second, session: session).code == nil)
    #expect(backend.calls == 1)
    coordinator.removeConnection(first)
    #expect(await perform(coordinator, connection: first, session: session).code == nil)
}

@Test @MainActor func supersededAndDisconnectedBackendCannotReplyTwice() async {
    let backend = TextBackend(); let coordinator = TextTranslationCoordinator(backend: backend)
    let connection = UUID(); let session = UUID().uuidString
    let (stream, events) = AsyncStream<Response>.makeStream()
    coordinator.translate(connectionID: connection, sessionID: session, generation: 1, text: "slow", target: "en") {
        events.yield(Response($0, $1, $2))
    }
    while backend.held == nil { await Task.yield() }
    coordinator.translate(connectionID: connection, sessionID: session, generation: 2, text: "Synthetic new", target: "en") {
        events.yield(Response($0, $1, $2))
    }
    backend.release()
    var responses: [Response] = []
    for await response in stream {
        responses.append(response)
        if responses.count == 2 { break }
    }
    #expect(responses.contains { $0.generation == 1 && $0.code == 4 && $0.text == nil })
    #expect(responses.contains { $0.generation == 2 && $0.code == nil && $0.text == "Synthetic translation" })
    #expect(await perform(coordinator, connection: connection, session: session, generation: 1).code == 2)
    let pending = Task { await perform(coordinator, connection: connection, session: session, generation: 3, text: "slow") }
    while backend.held == nil { await Task.yield() }
    coordinator.removeConnection(connection)
    #expect(await pending.value.code == 4)
    backend.release()
}

@Test @MainActor func markdownStructureRemainsExactAndCodeIsNotSubmitted() async throws {
    let source = "# Heading\r\n\r\n- Item  \n2. Second\n```swift\nlet x = 1\n```\n    indented\nTail\n"
    var submitted: [String] = []
    let output = try await StructuredTextTranslation.translate(source) {
        submitted.append($0); return "[" + $0 + "]"
    }
    #expect(output == "# [Heading]\r\n\r\n- [Item]  \n2. [Second]\n```swift\nlet x = 1\n```\n    indented\n[Tail]\n")
    #expect(submitted == ["Heading", "Item", "Second", "Tail"])
    await #expect(throws: CandidateTranslationFailure.invalidRequest) {
        try await StructuredTextTranslation.translate("Synthetic") { _ in "Changed\nstructure" }
    }
}

@Test @MainActor func textAndCandidateRoleBoundariesStaySeparate() async {
    let backend = TextBackend()
    let coordinator = TranslationCoordinator(textBackend: backend)
    let ime = TranslationXPCService(coordinator: coordinator, role: .inputMethod)
    let denied = await withCheckedContinuation { continuation in
        ime.translateText(sessionID: UUID().uuidString, generation: 1, text: "Synthetic", target: "en") { generation, text, error in
            continuation.resume(returning: Response(generation, text, error as NSError?))
        }
    }
    #expect(denied.code == 5); #expect(backend.calls == 0)
    let app = TranslationXPCService(coordinator: coordinator, role: .mainApp)
    let accepted = await withCheckedContinuation { continuation in
        app.translateText(sessionID: UUID().uuidString, generation: 1, text: "Synthetic", target: "fr") { generation, text, error in
            continuation.resume(returning: Response(generation, text, error as NSError?))
        }
    }
    #expect(accepted.text == "Synthetic translation")
    let candidate = await withCheckedContinuation { continuation in
        app.translateCandidate(sessionID: UUID().uuidString, generation: 1, request: [:]) { _, _, _, _, error in
            continuation.resume(returning: (error as NSError?)?.code)
        }
    }
    #expect(candidate == 5)
}

private final class Listener: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let service: TranslationXPCService
    private let lock = NSLock()
    private var connections: [NSXPCConnection] = []
    func invalidateConnections() {
        lock.lock(); let old = connections; connections.removeAll(); lock.unlock()
        old.forEach { $0.invalidate() }
    }
    init(_ service: TranslationXPCService) { self.service = service }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: RoarkTTextTranslationXPCProtocol.self)
        connection.exportedObject = service
        lock.lock(); connections.append(connection); lock.unlock()
        connection.resume()
        return true
    }
}

@Test @MainActor func realXPCTextRoundTripCancellationAndRebuild() async throws {
    let backend = TextBackend()
    let coordinator = TranslationCoordinator(textBackend: backend)
    let service = TranslationXPCService(coordinator: coordinator, role: .mainApp)
    let delegate = Listener(service)
    let listener = NSXPCListener.anonymous()
    listener.delegate = delegate; listener.resume()
    defer { delegate.invalidateConnections(); listener.invalidate() }
    var connections = 0
    let client = TextTranslationXPCClient(timeout: .seconds(3), makeConnection: {
        connections += 1
        return NSXPCConnection(listenerEndpoint: listener.endpoint)
    })
    let session = UUID()
    let first = try await client.translate(sessionID: session, generation: 1, text: "Synthetic", target: "fr")
    #expect(first == "Synthetic translation")
    let pending = Task { try await client.translate(sessionID: session, generation: 2, text: "slow", target: "fr") }
    while backend.held == nil { await Task.yield() }
    pending.cancel()
    await #expect(throws: CancellationError.self) { try await pending.value }
    backend.release()
    client.stop()
    #expect(try await client.translate(sessionID: UUID(), generation: 1, text: "Synthetic", target: "en") == "Synthetic translation")
    #expect(connections == 2)
    client.stop()
}

@Test @MainActor func xpcTimeoutFinishesAndRebuilds() async throws {
    let backend = TextBackend()
    let service = TranslationXPCService(coordinator: TranslationCoordinator(textBackend: backend), role: .mainApp)
    let delegate = Listener(service)
    let listener = NSXPCListener.anonymous(); listener.delegate = delegate; listener.resume()
    defer { delegate.invalidateConnections(); listener.invalidate() }
    let client = TextTranslationXPCClient(timeout: .milliseconds(150), makeConnection: {
        NSXPCConnection(listenerEndpoint: listener.endpoint)
    })
    await #expect(throws: TextTranslationXPCClient.Failure.timedOut) {
        try await client.translate(sessionID: UUID(), generation: 1, text: "slow", target: "en")
    }
    backend.release()
    #expect(try await client.translate(sessionID: UUID(), generation: 1, text: "Synthetic", target: "en") == "Synthetic translation")
    client.stop()
}

@Test @MainActor func xpcInterruptionFailsPendingAndNextCallReconnects() async throws {
    let backend = TextBackend()
    let service = TranslationXPCService(coordinator: TranslationCoordinator(textBackend: backend), role: .mainApp)
    let delegate = Listener(service)
    let listener = NSXPCListener.anonymous(); listener.delegate = delegate; listener.resume()
    defer { delegate.invalidateConnections(); listener.invalidate() }
    var count = 0
    let client = TextTranslationXPCClient(timeout: .seconds(2), makeConnection: {
        count += 1
        return NSXPCConnection(listenerEndpoint: listener.endpoint)
    })
    let pending = Task { try await client.translate(sessionID: UUID(), generation: 1, text: "slow", target: "en") }
    while backend.held == nil { await Task.yield() }
    delegate.invalidateConnections()
    await #expect(throws: TextTranslationXPCClient.Failure.disconnected) { try await pending.value }
    backend.release()
    #expect(try await client.translate(sessionID: UUID(), generation: 1, text: "Synthetic", target: "en") == "Synthetic translation")
    #expect(count == 2)
    client.stop()
}

@Test @MainActor func nestedListAndEmptyMarkerKeepStructure() async throws {
    let output = try await StructuredTextTranslation.translate("- \n    - Nested\n\t2. Nested\n") { "[" + $0 + "]" }
    #expect(output == "- \n    - [Nested]\n\t2. [Nested]\n")
}
