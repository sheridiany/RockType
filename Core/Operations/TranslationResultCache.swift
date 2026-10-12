import Foundation

/// Explicitly owned by the app operation environment. No persistence and no credentials.
@MainActor public final class TranslationResultCache {
    struct Key: Hashable {
        let text: String
        let languageSettings: Data
        let target: String
        let engine: String
        let model: String
        let connection: Data
        let prompt: String
    }
    private struct Entry { let text: String; let created: TimeInterval; var used: UInt64; let bytes: Int }
    private var entries: [Key: Entry] = [:]
    private var sequence: UInt64 = 0
    private let capacity: Int
    private let byteLimit: Int
    private let lifetime: TimeInterval
    private let clock: () -> TimeInterval
    public init(capacity: Int = 64, byteLimit: Int = 524_288, lifetime: TimeInterval = 300,
                clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.capacity = max(0, capacity); self.byteLimit = max(0, byteLimit)
        self.lifetime = max(0, lifetime); self.clock = clock
    }
    public func clear() { entries.removeAll() }
    func key(_ request: OperationRequest, target: String, engine: String, model: String,
             connection: AIConnectionSettings? = nil) -> Key? {
        let text = request.session.snapshot.text
        guard request.template.id == "translate", request.question == nil, request.session.turns.isEmpty,
              text.utf8.count <= 4096, text.count <= 500 else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let languages = try? encoder.encode(request.settings.translation),
              let config = try? encoder.encode(connection) else { return nil }
        return Key(text: text, languageSettings: languages, target: target, engine: engine, model: model,
                   connection: config, prompt: "protected-translation-v1\n" + OperationPrompts.resolved(request.template))
    }
    func value(for key: Key) -> String? {
        guard var entry = entries[key] else { return nil }
        guard clock() - entry.created < lifetime else { entries[key] = nil; return nil }
        sequence &+= 1; entry.used = sequence; entries[key] = entry
        return entry.text
    }
    func insert(_ text: String, for key: Key) {
        let bytes = text.utf8.count + key.text.utf8.count + key.prompt.utf8.count
            + key.languageSettings.count + key.connection.count + key.target.utf8.count + key.model.utf8.count + key.engine.utf8.count
        guard capacity > 0, bytes <= byteLimit else { return }
        entries = entries.filter { clock() - $0.value.created < lifetime }
        sequence &+= 1
        entries[key] = Entry(text: text, created: clock(), used: sequence, bytes: bytes)
        while entries.count > capacity || entries.values.reduce(0, { $0 + $1.bytes }) > byteLimit {
            guard let oldest = entries.min(by: { $0.value.used < $1.value.used })?.key else { break }
            entries[oldest] = nil
        }
    }
}
