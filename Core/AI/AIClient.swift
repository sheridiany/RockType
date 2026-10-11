import Foundation

public enum AIClientError: Error, Equatable, Sendable {
    case configuration, network, unauthorized, modelNotFound, rateLimited, server
    case decoding, timeout, cancelled, http(Int), responseTooLarge, emptyResponse, outputLimit
}

/// Stateless OpenAI Chat Completions transport. Credentials exist only for the duration of a call.
public struct AIClient: Sendable {
    public let connection: AIConnectionSettings
    private let session: URLSession
    public let timeout: TimeInterval
    private static let limit = 2 * 1024 * 1024

    public init(connection: AIConnectionSettings, session: URLSession = AIClient.makeSession(), timeout: TimeInterval = 90) {
        self.connection = connection; self.session = session; self.timeout = timeout
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }

    public func complete(text: String, apiKey: String, model: String? = nil, imageDataURL: String? = nil) async throws -> String {
        try await perform(text: text, apiKey: apiKey, model: model, imageDataURL: imageDataURL, stream: false, onThinking: {}) { _ in }
    }

    /// Runs in the caller's task: cancellation terminates the underlying URLSession request.
    /// Role/usage frames are ignored; reasoning emits only a status callback, never its text.
    public func stream(text: String, apiKey: String, model: String? = nil, imageDataURL: String? = nil,
                       onThinking: @escaping @Sendable () async -> Void = {},
                       onDelta: @escaping @Sendable (String) async -> Void) async throws -> String {
        try await perform(text: text, apiKey: apiKey, model: model, imageDataURL: imageDataURL, stream: true, onThinking: onThinking, onDelta: onDelta)
    }

    private func perform(text: String, apiKey: String, model: String?, imageDataURL: String?, stream: Bool,
                         onThinking: @escaping @Sendable () async -> Void,
                         onDelta: @escaping @Sendable (String) async -> Void) async throws -> String {
        guard timeout.isFinite, timeout > 0 else { throw AIClientError.configuration }
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await performAttempt(text: text, apiKey: apiKey, model: model, imageDataURL: imageDataURL,
                                         stream: stream, onThinking: onThinking, onDelta: onDelta)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw AIClientError.timeout
            }
            defer { group.cancelAll() }
            do { return try await group.next()! }
            catch { if Task.isCancelled { throw AIClientError.cancelled }; throw error }
        }
    }

    private func performAttempt(text: String, apiKey: String, model: String?, imageDataURL: String?, stream: Bool,
                                onThinking: @escaping @Sendable () async -> Void,
                                onDelta: @escaping @Sendable (String) async -> Void) async throws -> String {
        do {
            try Task.checkCancellation()
            let request = try makeRequest(text: text, apiKey: apiKey, model: model, imageDataURL: imageDataURL, stream: stream)
            let (bytes, response) = try await open(request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else { throw AIClientError.network }
            guard (200..<300).contains(http.statusCode) else { throw Self.httpError(http.statusCode) }
            if !stream {
                var data = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    guard data.count < Self.limit else { throw AIClientError.responseTooLarge }
                    data.append(byte)
                }
                try Task.checkCancellation()
                guard let reply = try? JSONDecoder().decode(Completion.self, from: data),
                      let choice = reply.choices.first else { throw AIClientError.decoding }
                if choice.finish_reason == "length" { throw AIClientError.outputLimit }
                return try Self.answer(choice.message.content ?? "")
            }
            var parser = SSEParser()
            var output = ""
            var received = 0
            var thinkingSignalled = false
            for try await byte in bytes {
                try Task.checkCancellation()
                received += 1
                guard received <= Self.limit else { throw AIClientError.responseTooLarge }
                if let event = try parser.append(byte) {
                    if event == "[DONE]" { return try Self.answer(output) }
                    guard let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(event.utf8)) else {
                        throw AIClientError.decoding
                    }
                    for choice in chunk.choices where choice.index == 0 {
                        if choice.finish_reason == "length" { throw AIClientError.outputLimit }
                        if output.isEmpty, !thinkingSignalled, choice.delta.reasoning_content?.isEmpty == false {
                            thinkingSignalled = true
                            await onThinking()
                            try Task.checkCancellation()
                        }
                        if let delta = choice.delta.content, !delta.isEmpty {
                            output += delta
                            await onDelta(delta)
                            try Task.checkCancellation()
                        }
                    }
                }
            }
            // A truncated stream must not masquerade as a successful completion.
            throw AIClientError.decoding
        } catch {
            if Task.isCancelled { throw AIClientError.cancelled }
            if let error = error as? AIClientError { throw error }
            if let error = error as? URLError {
                if error.code == .cancelled { throw AIClientError.cancelled }
                if error.code == .timedOut { throw AIClientError.timeout }
            }
            throw AIClientError.network
        }
    }

    private static func answer(_ text: String) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIClientError.emptyResponse }
        return text
    }

    /// Retry once only when the server rejects before any response content is consumed.
    /// Never replay a partial answer, an authentication failure or an ambiguous network failure.
    private func open(_ request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        for attempt in 0...1 {
            try Task.checkCancellation()
            let pair = try await session.bytes(for: request, delegate: NoAIRedirects())
            guard attempt == 0, let response = pair.1 as? HTTPURLResponse,
                  response.statusCode == 429 || (500...599).contains(response.statusCode) else { return pair }
            let delay: Double
            if let header = response.value(forHTTPHeaderField: "Retry-After") {
                // A date or a long server-requested delay is left for an explicit user retry.
                guard let seconds = Double(header) else { return pair }
                delay = seconds
            } else { delay = 0.5 }
            guard delay.isFinite, delay >= 0, delay <= 2 else { return pair }
            pair.0.task.cancel()
            try await Task.sleep(for: .seconds(delay))
        }
        throw AIClientError.server
    }

    /// HTTPS everywhere; plain HTTP only for a local relay on the loopback interface.
    public static func isAllowedEndpoint(_ url: URLComponents) -> Bool {
        guard let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]")), !host.isEmpty else { return false }
        if url.scheme == "https" { return true }
        return url.scheme == "http" && ["127.0.0.1", "::1", "localhost"].contains(host)
    }

    private func makeRequest(text: String, apiKey: String, model: String?, imageDataURL: String?, stream: Bool) throws -> URLRequest {
        guard timeout.isFinite, timeout > 0,
              var url = URLComponents(string: connection.baseURL), Self.isAllowedEndpoint(url),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !apiKey.contains("\r"), !apiKey.contains("\n") else { throw AIClientError.configuration }
        let selectedModel = model ?? connection.defaultModel
        guard !selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIClientError.configuration }
        url.path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        url.path = "/" + (url.path.isEmpty ? "" : url.path + "/") + "chat/completions"
        guard let endpoint = url.url else { throw AIClientError.configuration }
        let content: Any
        if let imageDataURL {
            guard (selectedModel == connection.defaultModel && connection.defaultModelSupportsImages) || selectedModel == connection.visionModel,
                  imageDataURL.hasPrefix("data:image/"), let comma = imageDataURL.firstIndex(of: ","),
                  imageDataURL[..<comma].hasSuffix(";base64"),
                  Data(base64Encoded: String(imageDataURL[imageDataURL.index(after: comma)...])) != nil else {
                throw AIClientError.configuration
            }
            content = [["type": "text", "text": text], ["type": "image_url", "image_url": ["url": imageDataURL]]] as [[String: Any]]
        } else { content = text }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "max_tokens": 8192, "model": selectedModel, "messages": [["role": "user", "content": content]], "stream": stream,
        ])
        return request
    }

    private static func httpError(_ status: Int) -> AIClientError {
        switch status {
        case 401, 403: .unauthorized
        case 404: .modelNotFound
        case 429: .rateLimited
        case 500...599: .server
        default: .http(status)
        }
    }
    private struct Completion: Decodable {
        struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message; let finish_reason: String? }
        let choices: [Choice]
    }
    private struct Chunk: Decodable {
        struct Choice: Decodable { struct Delta: Decodable { let content: String?; let reasoning_content: String? }; let index: Int; let delta: Delta; let finish_reason: String? }
        let choices: [Choice]
    }
}

private final class NoAIRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// SSE framing is byte-based so split UTF-8 and arbitrary network chunk boundaries are safe.
struct SSEParser {
    private var line = Data()
    private var dataLines: [String] = []
    private var size = 0
    private var previousWasCR = false
    mutating func append(_ byte: UInt8) throws -> String? {
        if byte == 10 && previousWasCR { previousWasCR = false; return nil }
        previousWasCR = byte == 13
        if byte != 10 && byte != 13 {
            guard size < 262_144 else { throw AIClientError.responseTooLarge }
            line.append(byte); size += 1
            return nil
        }
        guard var text = String(data: line, encoding: .utf8) else { throw AIClientError.decoding }
        line.removeAll(keepingCapacity: true)
        if text.isEmpty {
            defer { dataLines.removeAll(keepingCapacity: true); size = 0 }
            return dataLines.isEmpty ? nil : dataLines.joined(separator: "\n")
        }
        if text.hasPrefix("data:") {
            text.removeFirst(5)
            if text.first == " " { text.removeFirst() }
            dataLines.append(text)
        }
        return nil
    }
}
