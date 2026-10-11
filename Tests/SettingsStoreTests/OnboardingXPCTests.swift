import Foundation
import Testing
import RoarkTXPCProtocol
@testable import RoarkTApp

private final class OnboardingXPCService: NSObject, RoarkTTranslationXPCProtocol, @unchecked Sendable {
    let answers: Bool
    init(answers: Bool) { self.answers = answers }
    func ping(reply: @escaping (String) -> Void) { if answers { reply("2") } }
    func controllerInputGeneration(reply: @escaping (Int64, Error?) -> Void) { reply(42, nil) }
    func dictationEndpoint(reply: @escaping (NSXPCListenerEndpoint?) -> Void) { reply(nil) }
    func recordControllerInput() {}
    func registerDictationEndpoint(_ endpoint: NSXPCListenerEndpoint) {}
    func cancel(sessionID: String, throughGeneration: Int64) {}
    func translateCandidate(sessionID: String, generation: Int64, request: [String: String],
                            withReply reply: @escaping (Int64, String?, String?, String?, Error?) -> Void) {}
}

private final class OnboardingXPCListener: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let service: OnboardingXPCService
    init(answers: Bool = true) { service = OnboardingXPCService(answers: answers) }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: RoarkTTranslationXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

@MainActor @Test func onboardingXPCDiscoveryAndReconnection() async throws {
    let delegate = OnboardingXPCListener()
    let listener = NSXPCListener.anonymous()
    listener.delegate = delegate
    listener.resume()
    defer { listener.invalidate() }
    var connections = 0
    let client = TranslationServiceClient {
        connections += 1
        return NSXPCConnection(listenerEndpoint: listener.endpoint)
    }
    defer { client.invalidate() }
    #expect(try await client.ping() == "2")
    let before = try await client.controllerInputGeneration()
    #expect(before.value == 42)
    #expect(try await client.dictationEndpoint() == nil)
    #expect(connections == 1)
    client.invalidate()
    let after = try await client.controllerInputGeneration()
    #expect(before.connectionID != after.connectionID && connections == 2)
}

@MainActor @Test func onboardingXPCTimeoutRebuildsAndCancellationFinishes() async throws {
    let silentDelegate = OnboardingXPCListener(answers: false)
    let normalDelegate = OnboardingXPCListener()
    let silent = NSXPCListener.anonymous()
    silent.delegate = silentDelegate
    silent.resume()
    let normal = NSXPCListener.anonymous()
    normal.delegate = normalDelegate
    normal.resume()
    defer { silent.invalidate(); normal.invalidate() }
    var connections = 0
    let client = TranslationServiceClient {
        connections += 1
        return NSXPCConnection(listenerEndpoint: connections == 1 ? silent.endpoint : normal.endpoint)
    }
    defer { client.invalidate() }
    let cancelled = Task { try await client.ping() }
    // Yield until the request has been installed; cancellation must not wait for its timeout.
    while connections == 0 { await Task.yield() }
    cancelled.cancel()
    do { _ = try await cancelled.value; Issue.record("cancelled request succeeded") }
    catch { #expect(error is CancellationError) }
    do { _ = try await client.ping(); Issue.record("silent peer succeeded") }
    catch { #expect(error is TranslationServiceClient.Failure) }
    #expect(try await client.ping() == "2")
    #expect(connections == 2)
}
