import Foundation

public enum AIClientError: Error, Equatable, Sendable {
    case configuration, network, unauthorized, modelNotFound, rateLimited, server
    case decoding, timeout, cancelled, http(Int), responseTooLarge
}

/// Stateless OpenAI Chat Completions transport. Credentials exist only for the duration of a call.
public struct AIClient: Sendable {
    public let connection: AIConnectionSettings
    private let session: URLSession
    public let timeout: TimeInterval
    private static let limit = 2 * 1024 * 1024

    public init(connection: AIConnectionSettings, session: URLSession = AIClient.makeSession(), timeout: TimeInterval = 30) {
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
        try await perform(text: text, apiKey: apiKey, model: model, imageDataURL: imageDataURL, stream: false) { _ in }
    }

    /// Runs in the caller's task: cancellation terminates the underlying URLSession request.
    /// Deltas may be empty (role/usage frames). No request or response content is logged.
    public func stream(text: String, apiKey: String, model: String? = nil,
                       onDelta: @Sendable (String) async -> Void) async throws -> String {
        try await perform(text: text, apiKey: apiKey, model: model, imageDataURL: nil, stream: true, onDelta: onDelta)
    }

    private func perform(text: String, apiKey: String, model: String?, imageDataURL: String?, stream: Bool,
                         onDelta: @Sendable (String) async -> Void) async throws -> String {
        do {
            try Task.checkCancellation()
            let request = try makeRequest(text: text, apiKey: apiKey, model: model, imageDataURL: imageDataURL, stream: stream)
            let (bytes, response) = try await session.bytes(for: request, delegate: NoAIRedirects())
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
                      let content = reply.choices.first?.message.content else { throw AIClientError.decoding }
                return content
            }
            var parser = SSEParser()
            var output = ""
            var received = 0
            for try await byte in bytes {
                try Task.checkCancellation()
                received += 1
                guard received <= Self.limit else { throw AIClientError.responseTooLarge }
                if let event = try parser.append(byte) {
                    if event == "[DONE]" { return output }
                    guard let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(event.utf8)) else {
                        throw AIClientError.decoding
                    }
                    for choice in chunk.choices where choice.index == 0 {
                        if let delta = choice.delta.content {
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

    private func makeRequest(text: String, apiKey: String, model: String?, imageDataURL: String?, stream: Bool) throws -> URLRequest {
        guard timeout.isFinite, timeout > 0,
              var url = URLComponents(string: connection.baseURL), url.scheme == "https", url.host != nil,
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
            guard connection.defaultModelSupportsImages || selectedModel == connection.visionModel,
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
            "model": selectedModel, "messages": [["role": "user", "content": content]], "stream": stream,
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
        struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }
        let choices: [Choice]
    }
    private struct Chunk: Decodable {
        struct Choice: Decodable { struct Delta: Decodable { let content: String? }; let index: Int; let delta: Delta }
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
