import Foundation
import RoarkTCore

@MainActor
protocol SelectionTextTranslating: AnyObject {
    func translate(_ text: String, target: String) async throws -> String
}

/// Independent from candidate traffic: app generations never cancel IME work.
@MainActor
final class TextTranslationCoordinator {
    private struct Key: Hashable { let connection: UUID; let session: String }
    private struct Pending {
        let task: Task<Void, Never>
        let reply: @Sendable (Int64, String?, NSError?) -> Void
        let generation: Int64
    }
    private let backend: any SelectionTextTranslating
    private var latest: [Key: Int64] = [:]
    private var pending: [Key: Pending] = [:]
    static let maximumBytes = 131_072
    // Bound per-connection session watermarks rather than evicting them and accepting old work.
    private static let maximumSessions = 1_024

    init(backend: any SelectionTextTranslating = SelectionTranslatorFactory.make()) { self.backend = backend }

    func translate(connectionID: UUID, sessionID: String, generation: Int64, text: String, target: String,
                   reply: @escaping @Sendable (Int64, String?, NSError?) -> Void) {
        guard UUID(uuidString: sessionID) != nil, generation > 0,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= Self.maximumBytes,
              target.range(of: "^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8}){0,3}$", options: .regularExpression) != nil
        else { reply(generation, nil, Self.error(1)); return }
        let key = Key(connection: connectionID, session: sessionID)
        if let watermark = latest[key], generation <= watermark { reply(generation, nil, Self.error(2)); return }
        guard latest[key] != nil || latest.keys.filter({ $0.connection == connectionID }).count < Self.maximumSessions
        else { reply(generation, nil, Self.error(7)); return }
        latest[key] = generation
        cancelPending(key)
        let target = DefaultOperationRunner.targetLanguage(target, text: text)
        let task = Task { [weak self, backend] in
            do {
                try Task.checkCancellation()
                let translated = try await backend.translate(text, target: target)
                try Task.checkCancellation()
                guard let self, self.latest[key] == generation,
                      let active = self.pending.removeValue(forKey: key) else { return }
                guard !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      translated.utf8.count <= Self.maximumBytes * 4 else {
                    active.reply(generation, nil, Self.error(8)); return
                }
                active.reply(generation, translated, nil)
            } catch {
                guard let self, self.latest[key] == generation,
                      let active = self.pending.removeValue(forKey: key) else { return }
                active.reply(generation, nil, error is CancellationError ? Self.error(4)
                    : CandidateTranslationFailure.from(error) as NSError)
            }
        }
        pending[key] = Pending(task: task, reply: reply, generation: generation)
    }

    func cancel(connectionID: UUID, sessionID: String, throughGeneration: Int64) {
        guard UUID(uuidString: sessionID) != nil, throughGeneration > 0 else { return }
        let key = Key(connection: connectionID, session: sessionID)
        guard (latest[key] ?? 0) <= throughGeneration else { return }
        guard latest[key] != nil || latest.keys.filter({ $0.connection == connectionID }).count < Self.maximumSessions else { return }
        latest[key] = throughGeneration
        cancelPending(key)
    }

    func removeConnection(_ connectionID: UUID) {
        for key in latest.keys.filter({ $0.connection == connectionID }) {
            cancelPending(key); latest[key] = nil
        }
    }

    private func cancelPending(_ key: Key) {
        guard let active = pending.removeValue(forKey: key) else { return }
        active.task.cancel()
        // Complete immediately even if Apple's callback ignores cancellation.
        active.reply(active.generation, nil, Self.error(4))
    }

    nonisolated static func error(_ code: Int) -> NSError {
        let description: String
        switch code {
        case 1: description = "划词翻译请求无效或内容超过限制。"
        case 2: description = "翻译请求已过期。"
        case 4: description = "翻译已取消。"
        case 5: description = "此调用方无权使用划词翻译。"
        case 7: description = "翻译会话过多，请重新连接。"
        default: description = "翻译结果不可用。"
        }
        return NSError(domain: TranslationXPC.errorDomain, code: code,
            userInfo: [NSLocalizedDescriptionKey: description])
    }
}

extension TranslationXPCService {
    private final class TextReply: @unchecked Sendable {
        let call: (Int64, String?, Error?) -> Void
        init(_ call: @escaping (Int64, String?, Error?) -> Void) { self.call = call }
    }
    func translateText(sessionID: String, generation: Int64, text: String, target: String,
                       withReply reply: @escaping (Int64, String?, Error?) -> Void) {
        guard role == .mainApp else { reply(generation, nil, TextTranslationCoordinator.error(5)); return }
        let reply = TextReply(reply)
        Task { @MainActor [connectionID, coordinator] in
            coordinator.textTranslations.translate(connectionID: connectionID, sessionID: sessionID,
                generation: generation, text: text, target: target) { generation, text, error in
                    reply.call(generation, text, error)
                }
        }
    }
    func cancelText(sessionID: String, throughGeneration: Int64) {
        guard role == .mainApp else { return }
        Task { @MainActor [connectionID, coordinator] in
            coordinator.textTranslations.cancel(connectionID: connectionID, sessionID: sessionID,
                throughGeneration: throughGeneration)
        }
    }
}
