import Foundation
import Testing
@testable import RoarkTCore

/// Per-URL fixtures avoid shared mutable handlers when Swift Testing runs concurrently.
private final class AIStub: URLProtocol, @unchecked Sendable {
    struct Fixture: Sendable {
        var status = 200
        var chunks: [Data] = []
        var error: URLError.Code? = nil
        var hang = false
    }
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var fixtures: [String: Fixture] = [:]
        var requests: [String: URLRequest] = [:]
        var stopped = Set<String>()
        func use<T>(_ body: (State) -> T) -> T { lock.lock(); defer { lock.unlock() }; return body(self) }
    }
    private static let state = State()
    static func install(_ fixture: Fixture, host: String) { state.use { $0.fixtures[host] = fixture } }
    static func request(_ host: String) -> URLRequest? { state.use { $0.requests[host] } }
    static func wasStopped(_ host: String) -> Bool { state.use { $0.stopped.contains(host) } }
    static func remove(_ host: String) { state.use { $0.fixtures[host] = nil; $0.requests[host] = nil; $0.stopped.remove(host) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let host = request.url!.host!
        let fixture = Self.state.use { state in
            state.requests[host] = request
            return state.fixtures[host]
        }
        guard let fixture else { client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return }
        if let error = fixture.error { client?.urlProtocol(self, didFailWithError: URLError(error)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: fixture.status,
                                                           httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!, cacheStoragePolicy: .notAllowed)
        for data in fixture.chunks { client?.urlProtocol(self, didLoad: data) }
        if !fixture.hang { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() {
        if let host = request.url?.host { Self.state.use { $0.stopped.insert(host) } }
    }
}

private func makeClient(_ fixture: AIStub.Fixture, images: Bool = false) -> (AIClient, String, URLSession) {
    let host = UUID().uuidString.lowercased() + ".invalid"
    AIStub.install(fixture, host: host)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AIStub.self]
    let session = URLSession(configuration: configuration)
    var connection = AIConnectionSettings()
    connection.baseURL = "https://\(host)/v1/"
    connection.defaultModel = "test-model"
    connection.defaultModelSupportsImages = images
    return (AIClient(connection: connection, session: session), host, session)
}
private let completion = Data(#"{"choices":[{"message":{"content":"测试成功"}}]}"#.utf8)

@Test func aiCompletionAndImageUseConfiguredRequest() async throws {
    let (client, host, session) = makeClient(.init(chunks: [completion]), images: true)
    defer { session.invalidateAndCancel(); AIStub.remove(host) }
    #expect(try await client.complete(text: "Synthetic probe", apiKey: "synthetic-key",
                                     imageDataURL: "data:image/png;base64,AA==") == "测试成功")
    let request = try #require(AIStub.request(host))
    #expect(request.url?.path == "/v1/chat/completions")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-key")
    #expect(request.httpMethod == "POST")
    let body: Data
    if let data = request.httpBody { body = data }
    else {
        let stream = try #require(request.httpBodyStream)
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        body = data
    }
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["model"] as? String == "test-model")
    #expect(String(decoding: body, as: UTF8.self).contains("image_url"))
}

private actor DeltaCollector {
    var text = ""
    func append(_ delta: String) { text += delta }
}
@Test func aiSSEHandlesUTF8CommentsCRLFAndRoleFrames() async throws {
    let sse = ": keepalive\r\ndata: {\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\r\n\r\ndata: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"你好\"}}]}\n\ndata: [DONE]\n\n"
    let (client, host, session) = makeClient(.init(chunks: sse.utf8.map { Data([$0]) }))
    defer { session.invalidateAndCancel(); AIStub.remove(host) }
    let collector = DeltaCollector()
    let result = try await client.stream(text: "Probe", apiKey: "synthetic-key") { await collector.append($0) }
    #expect(result == "你好")
    #expect(await collector.text == "你好")
}

@Test(arguments: [(401, AIClientError.unauthorized), (403, .unauthorized), (404, .modelNotFound),
                  (429, .rateLimited), (503, .server), (400, .http(400)), (302, .http(302))])
func aiHTTPFailuresAreClassified(status: Int, expected: AIClientError) async throws {
    let (client, host, session) = makeClient(.init(status: status, chunks: [Data("do not expose response".utf8)]))
    defer { session.invalidateAndCancel(); AIStub.remove(host) }
    await #expect(throws: expected) { try await client.complete(text: "Probe", apiKey: "synthetic-key") }
}

@Test(arguments: [(URLError.Code.timedOut, AIClientError.timeout), (.notConnectedToInternet, .network)])
func aiTransportFailuresAreClassified(code: URLError.Code, expected: AIClientError) async throws {
    let (client, host, session) = makeClient(.init(error: code))
    defer { session.invalidateAndCancel(); AIStub.remove(host) }
    await #expect(throws: expected) { try await client.complete(text: "Probe", apiKey: "synthetic-key") }
}

@Test func aiRejectsMalformedAndTruncatedResponses() async throws {
    let (client, host, session) = makeClient(.init(chunks: [Data("data: {}\n\n".utf8)]))
    defer { session.invalidateAndCancel(); AIStub.remove(host) }
    await #expect(throws: AIClientError.decoding) { try await client.complete(text: "Probe", apiKey: "synthetic-key") }
    await #expect(throws: AIClientError.decoding) { try await client.stream(text: "Probe", apiKey: "synthetic-key") { _ in } }
    AIStub.install(.init(chunks: [Data("data: {\"choices\":[]}\n\n".utf8)]), host: host)
    await #expect(throws: AIClientError.decoding) { try await client.stream(text: "Probe", apiKey: "synthetic-key") { _ in } }
}

@Test func aiCancellationStopsTheActiveTransport() async throws {
    let (client, host, session) = makeClient(.init(hang: true))
    defer { session.invalidateAndCancel(); AIStub.remove(host) }
    let task = Task { try await client.stream(text: "Probe", apiKey: "synthetic-key") { _ in } }
    for _ in 0..<100 where AIStub.request(host) == nil { try await Task.sleep(for: .milliseconds(5)) }
    #expect(AIStub.request(host) != nil)
    task.cancel()
    await #expect(throws: AIClientError.cancelled) { try await task.value }
    for _ in 0..<100 where !AIStub.wasStopped(host) { try await Task.sleep(for: .milliseconds(5)) }
    #expect(AIStub.wasStopped(host))
}

@Test func aiInvalidConfigurationDoesNotStartRequest() async throws {
    let (client, host, session) = makeClient(.init(chunks: [completion]))
    defer { session.invalidateAndCancel(); AIStub.remove(host) }
    await #expect(throws: AIClientError.configuration) { try await client.complete(text: "Probe", apiKey: "") }
    await #expect(throws: AIClientError.configuration) {
        try await client.complete(text: "Probe", apiKey: "synthetic-key", imageDataURL: "data:image/png;base64,AA==")
    }
    var connection = client.connection
    connection.baseURL = "https://\(host)/v1?secret=value"
    await #expect(throws: AIClientError.configuration) {
        try await AIClient(connection: connection, session: session).complete(text: "Probe", apiKey: "synthetic-key")
    }
    #expect(AIStub.request(host) == nil)
}

@Test func aiConnectionTestReportsIndependentFailuresAndUnverifiedImage() async throws {
    let (client, host, session) = makeClient(.init(status: 401))
    defer { session.invalidateAndCancel(); AIStub.remove(host) }
    let result = try await AIConnectionTester(client: client).run(apiKey: "synthetic-key")
    #expect(result.text == .unavailable(.unauthorized))
    #expect(result.streaming == .unavailable(.unauthorized))
    #expect(result.image == .unverified)
    #expect(result.cancellation == .unavailable(.unauthorized))
}

@Test func sseSupportsMultilineEventsAndBoundsMalformedInput() throws {
    var parser = SSEParser()
    var events: [String] = []
    for byte in "event: message\ndata: first\ndata: second\n\n".utf8 {
        if let event = try parser.append(byte) { events.append(event) }
    }
    #expect(events == ["first\nsecond"])
    for _ in 0..<262_144 { _ = try parser.append(65) }
    #expect(throws: AIClientError.responseTooLarge) { try parser.append(65) }
}
