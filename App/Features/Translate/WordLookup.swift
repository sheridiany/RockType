import Foundation
import CoreServices
import RoarkTPlatform

/// Local-only, no cache. Call from a cancellable task tied to the source text.
@MainActor final class WordLookup {
    struct Sense: Equatable, Sendable {
        var partOfSpeech: String?
        var meaning: String
    }
    struct Definition: Equatable, Sendable {
        var term: String
        var pronunciation: String?
        var senses: [Sense]
    }
    typealias Provider = @Sendable (String) async -> String?
    private let provider: Provider
    private let allowed: @MainActor @Sendable () -> Bool

    init(allowed: @escaping @MainActor @Sendable () -> Bool = { SecureInput.status() == .allowed },
         provider: Provider? = nil) {
        self.allowed = allowed
        self.provider = provider ?? { term in await LocalDictionary.shared.definition(term, allowed: allowed) }
    }

    func lookup(_ text: String) async -> Definition? {
        guard !Task.isCancelled, allowed(), let term = Self.normalizedTerm(text) else { return nil }
        guard let raw = await provider(term), !Task.isCancelled, allowed() else { return nil }
        return WordDefinitionParser.parse(raw, term: term)
    }

    nonisolated static func normalizedTerm(_ text: String) -> String? {
        guard text.utf8.count <= 256 else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "‐", with: "-").replacingOccurrences(of: "‑", with: "-")
        guard !trimmed.contains(where: \.isNewline) else { return nil }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard (1...3).contains(words.count), words.allSatisfy({
            $0.range(of: #"^[A-Za-z]+(?:-[A-Za-z]+)*$"#, options: .regularExpression) != nil
        }) else { return nil }
        let term = words.joined(separator: " ")
        return term.count <= 96 ? term : nil
    }
}

/// DictionaryServices is synchronous; serialize it off the UI executor.
private actor LocalDictionary {
    static let shared = LocalDictionary()
    func definition(_ term: String, allowed: @MainActor @Sendable () -> Bool) async -> String? {
        guard !Task.isCancelled, await allowed(), !Task.isCancelled else { return nil }
        let text = term as CFString
        guard let definition = DCSCopyTextDefinition(nil, text, CFRange(location: 0, length: CFStringGetLength(text))) else { return nil }
        let result = definition.takeRetainedValue() as String
        return Task.isCancelled ? nil : result
    }
}
