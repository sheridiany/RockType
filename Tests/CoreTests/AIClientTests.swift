import Foundation
import Testing
@testable import RoarkTCore

/// Per-URL fixtures avoid shared mutable handlers when Swift Testing runs concurrently.
final class AIStub: URLProtocol, @unchecked Sendable {
    struct Fixture: Sendable {
        var status = 200
        var firstStatus: Int? = nil
        var retryAfter: String? = nil
        var chunks: [Data] = []
        var error: URLError.Code? = nil
        var hang = false
        var connectionProbe = false
    }
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var fixtures: [String: Fixture] = [:]
        var requests: [String: URLRequest] = [:]
        var requestCounts: [String: Int] = [:]
        var stopped = Set<String>()
        func use<T>(_ body: (State) -> T) -> T { lock.lock(); defer { lock.unlock() }; return body(self) }
    }
    private static let state = State()
    static func install(_ fixture: Fixture, host: String) { state.use { $0.fixtures[host] = fixture } }
    static func request(_ host: String) -> URLRequest? { state.use { $0.requests[host] } }
    static func count(_ host: String) -> Int { state.use { $0.requestCounts[host, default: 0] } }
    static func wasStopped(_ host: String) -> Bool { state.use { $0.stopped.contains(host) } }
    static func remove(_ host: String) { state.use { $0.fixtures[host] = nil; $0.requests[host] = nil; $0.requestCounts[host] = nil; $0.stopped.remove(host) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let host = request.url!.host!
        let fixture: Fixture? = Self.state.use { state in
            state.requests[host] = request
            state.requestCounts[host, default: 0] += 1
            guard let fixture = state.fixtures[host] else { return nil }
            if state.requestCounts[host] == 1, let status = fixture.firstStatus { return Fixture(status: status) }
            guard fixture.connectionProbe else { return fixture }
            switch state.requestCounts[host] {
            case 1, 3: return Fixture(chunks: [completion])
            case 2: return Fixture(chunks: [Data("data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"OK\"}}]}\n\ndata: [DONE]\n\n".utf8)])
            default: return Fixture(hang: true)
            }
        }
        guard let fixture else { client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return }
        if let error = fixture.error { client?.urlProtocol(self, didFailWithError: URLError(error)); return }
        var headers = ["Content-Type": "text/event-stream"]
        headers["Retry-After"] = fixture.retryAfter
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: fixture.status,
                                                           httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        for data in fixture.chunks { client?.urlProtocol(self, didLoad: data) }
        if !fixture.hang { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() {
        if let host = request.url?.host { Self.state.use { $0.stopped.insert(host) } }
    }
}

func makeClient(_ fixture: AIStub.Fixture, images: Bool = false) -> (AIClient, String, URLSession) {
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
    #expect(json["max_tokens"] as? Int == 8192)
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

@Test func aiConnectionTestVerifiesAllFourCapabilities() async throws {
    let (client, host, session) = makeClient(.init(connectionProbe: true), images: true)
    defer { session.invalidateAndCancel(); AIStub.remove(host) }
    let result = try await AIConnectionTester(client: client).run(apiKey: "synthetic-key")
    #expect(result.text == .available)
    #expect((result.textLatency ?? 0) > 0)
    #expect(result.streaming == .available)
    #expect(result.image == .available)
    #expect(result.cancellation == .available)
    #expect(AIStub.wasStopped(host))
}

@Test func aiImageCapabilityBelongsToSelectedModel() async throws {
    let (client, host, session) = makeClient(.init(chunks: [completion]), images: true)
    defer { session.invalidateAndCancel(); AIStub.remove(host) }
    await #expect(throws: AIClientError.configuration) {
        try await client.complete(text: "Probe", apiKey: "synthetic-key", model: "unverified-model",
                                  imageDataURL: "data:image/png;base64,AA==")
    }
    #expect(AIStub.request(host) == nil)
}

@Test func endpointPolicyAllowsHTTPOnlyOnLoopback() {
    func allowed(_ text: String) -> Bool { URLComponents(string: text).map(AIClient.isAllowedEndpoint) ?? false }
    #expect(allowed("https://api.example.com/v1"))
    #expect(allowed("http://127.0.0.1:3425/v1"))
    #expect(allowed("http://localhost:8080/v1"))
    #expect(allowed("http://[::1]:3425/v1"))
    #expect(!allowed("http://api.example.com/v1"))
    #expect(!allowed("http://192.168.1.5/v1"))
    #expect(!allowed("ftp://127.0.0.1/v1"))
}

private actor AIProgressCollector {
    var events: [String] = []
    func thinking() { events.append("thinking") }
    func delta(_ text: String) { events.append(text) }
}

@Test func reasoningIsStatusOnlyAndFinalTextIsDeliveredOnce() async throws {
    let sse = """
    data: {"choices":[{"index":0,"delta":{"content":null,"reasoning_content":"synthetic hidden reasoning"}}]}

    data: {"choices":[{"index":0,"delta":{"content":"Visible answer"}}]}

    data: [DONE]


    """
    let (client, host, session) = makeClient(.init(chunks: sse.utf8.map { Data([$0]) }))
    defer { session.invalidateAndCancel(); AIStub.remove(host) }
    let collector = AIProgressCollector()
    let answer = try await client.stream(text: "Probe", apiKey: "synthetic-key",
        onThinking: { await collector.thinking() }, onDelta: { await collector.delta($0) })
    #expect(answer == "Visible answer")
    #expect(await collector.events == ["thinking", "Visible answer"])
}

@Test(arguments: ["null", "\"\"", "\"  \\n\""])
func missingFinalContentIsNotSuccess(content: String) async throws {
    let data = Data("{\"choices\":[{\"message\":{\"content\":\(content),\"reasoning_content\":\"hidden\"}}]}".utf8)
    let (client, host, session) = makeClient(.init(chunks: [data]))
    defer { session.invalidateAndCancel(); AIStub.remove(host) }
    await #expect(throws: AIClientError.emptyResponse) { try await client.complete(text: "Probe", apiKey: "synthetic-key") }
    AIStub.install(.init(chunks: [Data("data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\(content),\"reasoning_content\":\"hidden\"}}]}\n\ndata: [DONE]\n\n".utf8)]), host: host)
    await #expect(throws: AIClientError.emptyResponse) { try await client.stream(text: "Probe", apiKey: "synthetic-key") { _ in } }
}

@Test func outputLimitIsActionableForBothResponseModes() async throws {
    let data = Data(#"{"choices":[{"message":{"content":"partial"},"finish_reason":"length"}]}"#.utf8)
    let (client, host, session) = makeClient(.init(chunks: [data]))
    defer { session.invalidateAndCancel(); AIStub.remove(host) }
    await #expect(throws: AIClientError.outputLimit) { try await client.complete(text: "Probe", apiKey: "synthetic-key") }
    AIStub.install(.init(chunks: [Data("data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"partial\"},\"finish_reason\":\"length\"}]}\n\n".utf8)]), host: host)
    await #expect(throws: AIClientError.outputLimit) { try await client.stream(text: "Probe", apiKey: "synthetic-key") { _ in } }
}

@Test func transientRejectionRetriesButPartialStreamNeverReplays() async throws {
    let (client, host, session) = makeClient(.init(firstStatus: 503, chunks: [completion]))
    defer { session.invalidateAndCancel(); AIStub.remove(host) }
    #expect(try await client.complete(text: "Probe", apiKey: "synthetic-key") == "测试成功")
    #expect(AIStub.count(host) == 2)
    AIStub.install(.init(chunks: [Data("data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"partial\"}}]}\n\n".utf8)]), host: host)
    await #expect(throws: AIClientError.decoding) { try await client.stream(text: "Probe", apiKey: "synthetic-key") { _ in } }
    #expect(AIStub.count(host) == 3)
}

@Test func wholeRequestDeadlineStopsAnOpenStream() async throws {
    let (base, host, session) = makeClient(.init(hang: true))
    defer { session.invalidateAndCancel(); AIStub.remove(host) }
    let client = AIClient(connection: base.connection, session: session, timeout: 0.05)
    await #expect(throws: AIClientError.timeout) { try await client.stream(text: "Probe", apiKey: "synthetic-key") { _ in } }
    for _ in 0..<100 where !AIStub.wasStopped(host) { try await Task.sleep(for: .milliseconds(5)) }
    #expect(AIStub.wasStopped(host))
}

@Test func cancellationDuringRetryBackoffDoesNotResend() async throws {
    let (client, host, session) = makeClient(.init(status: 503))
    defer { session.invalidateAndCancel(); AIStub.remove(host) }
    let task = Task { try await client.complete(text: "Probe", apiKey: "synthetic-key") }
    for _ in 0..<100 where AIStub.count(host) == 0 { try await Task.sleep(for: .milliseconds(2)) }
    task.cancel()
    await #expect(throws: AIClientError.cancelled) { try await task.value }
    #expect(AIStub.count(host) == 1)
}

@Test(arguments: ["120", "Wed, 21 Oct 2037 07:28:00 GMT"])
func retryDoesNotIgnoreServerRequestedDelay(header: String) async throws {
    let (client, host, session) = makeClient(.init(status: 429, retryAfter: header))
    defer { session.invalidateAndCancel(); AIStub.remove(host) }
    await #expect(throws: AIClientError.rateLimited) { try await client.complete(text: "Probe", apiKey: "synthetic-key") }
    #expect(AIStub.count(host) == 1)
}

private actor RequestPermission {
    var checks = 0
    func allowFirstOnly() -> Bool { checks += 1; return checks == 1 }
}
@Test func transportRechecksPermissionBeforeRetryAndBeforeFirstRequest() async throws {
    let (base, host, session) = makeClient(.init(status: 503))
    defer { session.invalidateAndCancel(); AIStub.remove(host) }
    let blocked = AIClient(connection: base.connection, session: session, requestAllowed: { false })
    await #expect(throws: AIClientError.cancelled) { try await blocked.complete(text: "Synthetic", apiKey: "synthetic") }
    #expect(AIStub.count(host) == 0)
    let permission = RequestPermission()
    let changes = AIClient(connection: base.connection, session: session, requestAllowed: { await permission.allowFirstOnly() })
    await #expect(throws: AIClientError.cancelled) { try await changes.complete(text: "Synthetic", apiKey: "synthetic") }
    #expect(AIStub.count(host) == 1)
    #expect(await permission.checks == 2)
}
