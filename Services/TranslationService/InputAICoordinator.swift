import Carbon
import Foundation
import RoarkTCore
import RoarkTXPCProtocol

/// Values are fixed protocol codes, never provider error bodies or user content.
enum InputAIError: Int, Error {
    case invalidRequest = 100, notConfigured, stale, cancelled, unauthorized, secureInput
    case timeout, authentication, modelUnavailable, rateLimited, network, invalidResponse, capacity
    var nsError: NSError {
        let message: String
        switch self {
        case .invalidRequest: message = "输入法 AI 请求或配置无效。"
        case .notConfigured: message = "未配置 AI，请前往设置。"
        case .stale: message = "AI 请求已过期。"
        case .cancelled: message = "AI 请求已取消。"
        case .unauthorized: message = "此调用方无权执行此 AI 操作。"
        case .secureInput: message = "安全输入期间不可使用 AI。"
        case .timeout: message = "AI 请求超时，请重试。"
        case .authentication: message = "请检查 AI 密钥与模型权限。"
        case .modelUnavailable: message = "AI 模型不可用。"
        case .rateLimited: message = "AI 请求限流，请稍后重试。"
        case .network: message = "AI 服务连接失败，请重试。"
        case .invalidResponse: message = "AI 返回内容不可用。"
        case .capacity: message = "AI 会话过多，请重新连接。"
        }
        return NSError(domain: TranslationXPC.errorDomain, code: rawValue,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }
    static func from(_ error: Error) -> Self {
        if error is CancellationError { return .cancelled }
        switch error as? AIClientError {
        case .configuration: return .invalidRequest
        case .timeout: return .timeout
        case .cancelled: return .cancelled
        case .unauthorized: return .authentication
        case .modelNotFound: return .modelUnavailable
        case .rateLimited: return .rateLimited
        case .decoding, .responseTooLarge: return .invalidResponse
        default: return .network
        }
    }
}

struct InputAIConfiguration: Sendable {
    let connection: AIConnectionSettings
    let apiKey: String
    let timeout: TimeInterval
    let prompts: [String: String]

    init(_ values: [String: String]) throws {
        let keys: Set<String> = ["baseURL", "model", "apiKey", "timeout", "rewritePrompt", "polishPrompt", "translatePrompt"]
        guard Set(values.keys) == keys,
              values.values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 32_768 }),
              let url = URLComponents(string: values["baseURL"]!), AIClient.isAllowedEndpoint(url),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              let timeout = Double(values["timeout"]!), timeout.isFinite, (0.1...120).contains(timeout),
              !values["apiKey"]!.contains("\r"), !values["apiKey"]!.contains("\n") else {
            throw InputAIError.invalidRequest
        }
        var connection = AIConnectionSettings()
        connection.baseURL = values["baseURL"]!; connection.defaultModel = values["model"]!
        self.connection = connection; self.apiKey = values["apiKey"]!; self.timeout = timeout
        prompts = ["rewrite": values["rewritePrompt"]!, "polish": values["polishPrompt"]!, "translate": values["translatePrompt"]!]
    }

    @MainActor func prompt(text: String, action: String) -> String {
        let target = DefaultOperationRunner.targetLanguage("auto", text: text)
        // Match the existing operation-template syntax; append the snapshot exactly once.
        return prompts[action]!.replacingOccurrences(of: "{{target}}", with: target) + "\n\n" + text
    }
}

@MainActor
final class InputAICoordinator {
    typealias Reply = @Sendable (Int64, String?, String?, NSError?) -> Void
    typealias Complete = @Sendable (InputAIConfiguration, String) async throws -> String
    typealias DeadlineWait = @Sendable (Duration) async throws -> Void
    private struct Key: Hashable { let connection: UUID; let session: String }
    private struct Pending {
        let generation: Int64
        let reply: Reply
        let task: Task<Void, Never>
        let deadline: Task<Void, Never>
    }
    private var configuration: InputAIConfiguration?
    private var owner: UUID?
    private var latest: [Key: Int64] = [:]
    private var pending: [Key: Pending] = [:]
    private var protectionWatch: Task<Void, Never>?
    private let isSecure: () -> Bool
    private let complete: Complete
    private let waitForDeadline: DeadlineWait

    init(isSecure: @escaping () -> Bool = { IsSecureEventInputEnabled() },
         waitForDeadline: @escaping DeadlineWait = { try await Task.sleep(for: $0) },
         complete: @escaping Complete = { config, prompt in
             try await AIClient(connection: config.connection, timeout: config.timeout)
                 .complete(text: prompt, apiKey: config.apiKey)
         }) {
        self.isSecure = isSecure; self.complete = complete; self.waitForDeadline = waitForDeadline
    }

    func configure(_ values: [String: String], owner: UUID) -> NSError? {
        // A closing old app connection must not revoke a newer connection's config.
        if values.isEmpty {
            if self.owner == owner { clearConfiguration() }
            return nil
        }
        // A broken replacement must revoke the previous credential too.
        clearConfiguration()
        do { configuration = try InputAIConfiguration(values); self.owner = owner; return nil }
        catch { return InputAIError.invalidRequest.nsError }
    }

    private func clearConfiguration() {
        configuration = nil; owner = nil
        for key in Array(pending.keys) { finish(key, error: .cancelled) }
    }

    func rewrite(connectionID: UUID, sessionID: String, generation: Int64, text: String,
                 action: String, reply: @escaping Reply) {
        guard UUID(uuidString: sessionID) != nil, generation > 0,
              ["rewrite", "polish", "translate"].contains(action),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 131_072 else {
            reply(generation, nil, nil, InputAIError.invalidRequest.nsError); return
        }
        let key = Key(connection: connectionID, session: sessionID)
        guard generation > (latest[key] ?? 0) else { reply(generation, nil, nil, InputAIError.stale.nsError); return }
        guard latest[key] != nil || latest.keys.filter({ $0.connection == connectionID }).count < 1_024 else {
            reply(generation, nil, nil, InputAIError.capacity.nsError); return
        }
        latest[key] = generation
        finish(key, error: .cancelled)
        guard !isSecure() else { reply(generation, nil, nil, InputAIError.secureInput.nsError); return }
        guard let configuration else { reply(generation, nil, nil, InputAIError.notConfigured.nsError); return }
        let task = Task { [weak self, complete] in
            do {
                try Task.checkCancellation()
                let result = try await complete(configuration, configuration.prompt(text: text, action: action))
                try Task.checkCancellation()
                guard let self, self.pending[key]?.generation == generation else { return }
                guard !self.isSecure() else { self.finish(key, error: .secureInput); return }
                guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, result.utf8.count <= 524_288 else {
                    self.finish(key, error: .invalidResponse); return
                }
                self.finish(key, source: text, result: result)
            } catch {
                guard let self, self.pending[key]?.generation == generation else { return }
                self.finish(key, error: InputAIError.from(error))
            }
        }
        let deadline = Task { [weak self, waitForDeadline] in
            do {
                try Task.checkCancellation()
                try await waitForDeadline(.seconds(configuration.timeout))
                try Task.checkCancellation()
            } catch { return }
            guard self?.pending[key]?.generation == generation else { return }
            self?.finish(key, error: .timeout)
        }
        pending[key] = Pending(generation: generation, reply: reply, task: task, deadline: deadline)
        if protectionWatch == nil {
            protectionWatch = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                    guard let self else { return }
                    if self.isSecure() {
                        for key in Array(self.pending.keys) { self.finish(key, error: .secureInput) }
                    }
                }
            }
        }
    }

    func cancel(connectionID: UUID, sessionID: String, throughGeneration: Int64) {
        guard UUID(uuidString: sessionID) != nil, throughGeneration > 0 else { return }
        let key = Key(connection: connectionID, session: sessionID)
        guard (latest[key] ?? 0) <= throughGeneration,
              latest[key] != nil || latest.keys.filter({ $0.connection == connectionID }).count < 1_024 else { return }
        latest[key] = throughGeneration; finish(key, error: .cancelled)
    }

    func removeConnection(_ connectionID: UUID) {
        if owner == connectionID { clearConfiguration() }
        for key in latest.keys.filter({ $0.connection == connectionID }) {
            finish(key, error: .cancelled); latest[key] = nil
        }
    }

    private func finish(_ key: Key, source: String? = nil, result: String? = nil, error: InputAIError? = nil) {
        guard let active = pending.removeValue(forKey: key) else { return }
        active.task.cancel(); active.deadline.cancel()
        if pending.isEmpty { protectionWatch?.cancel(); protectionWatch = nil }
        active.reply(active.generation, source, result, error?.nsError)
    }
}

extension TranslationXPCService {
    private final class ConfigurationReply: @unchecked Sendable {
        let call: (Error?) -> Void
        init(_ call: @escaping (Error?) -> Void) { self.call = call }
    }
    private final class AIReply: @unchecked Sendable {
        let call: (Int64, String?, String?, Error?) -> Void
        init(_ call: @escaping (Int64, String?, String?, Error?) -> Void) { self.call = call }
    }
    func configureAI(config: [String: String], withReply reply: @escaping (Error?) -> Void) {
        guard role == .mainApp else { reply(InputAIError.unauthorized.nsError); return }
        let reply = ConfigurationReply(reply)
        Task { @MainActor [connectionID, coordinator] in
            reply.call(coordinator.inputAI.configure(config, owner: connectionID))
        }
    }
    func rewriteCandidate(sessionID: String, generation: Int64, text: String, action: String,
                          withReply reply: @escaping (Int64, String?, String?, Error?) -> Void) {
        guard role == .inputMethod else { reply(generation, nil, nil, InputAIError.unauthorized.nsError); return }
        let reply = AIReply(reply)
        Task { @MainActor [connectionID, coordinator] in
            coordinator.rewrite(connectionID: connectionID, sessionID: sessionID, generation: generation,
                                text: text, action: action) { reply.call($0, $1, $2, $3) }
        }
    }
}
