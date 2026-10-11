import Foundation
import NaturalLanguage
import RoarkTCore
@preconcurrency import Translation

/// Keep exact line endings, blank lines, Markdown prefixes and fenced code.
/// Wrapped paragraph lines are translated separately so layout cannot be collapsed.
@MainActor
enum StructuredTextTranslation {
    static func translate(_ text: String, transform: (String) async throws -> String) async throws -> String {
        let linePattern = try NSRegularExpression(pattern: "([^\\r\\n]*)(\\r\\n|\\r|\\n|$)")
        let prefixPattern = try NSRegularExpression(pattern: "^([ \\t]*(?:#{1,6}[ \\t]+|[-*+][ \\t]+|[0-9]+[.)][ \\t]+|>[ \\t]*)?)(.*?)([ \\t]*)$")
        let ns = text as NSString
        var output = ""
        var fence: (character: Character, count: Int)?
        for match in linePattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) where match.range.length > 0 {
            try Task.checkCancellation()
            let line = ns.substring(with: match.range(at: 1))
            let newline = ns.substring(with: match.range(at: 2))
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let first = trimmed.first
            let fenceCount = (first == "`" || first == "~") ? trimmed.prefix(while: { $0 == first }).count : 0
            if let active = fence {
                output += line + newline
                if first == active.character, fenceCount >= active.count,
                   trimmed.dropFirst(fenceCount).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                continue
            }
            if fenceCount >= 3, let first {
                fence = (first, fenceCount); output += line + newline; continue
            }
            // Markdown indented code also remains local and unchanged.
            let isList = trimmed.range(of: "^(?:[-*+]|[0-9]+[.)])[ \t]+", options: .regularExpression) != nil
            if trimmed.isEmpty || (!isList && (line.hasPrefix("    ") || line.hasPrefix("\t"))) {
                output += line + newline; continue
            }
            let value = line as NSString
            guard let pieces = prefixPattern.firstMatch(in: line, range: NSRange(location: 0, length: value.length)) else {
                throw CandidateTranslationFailure.invalidRequest
            }
            let content = value.substring(with: pieces.range(at: 2))
            if content.isEmpty { output += line + newline; continue }
            let translated = try await transform(content)
            try Task.checkCancellation()
            // A backend inserting paragraph breaks would corrupt the original structure.
            guard !translated.contains("\n"), !translated.contains("\r"), !translated.isEmpty else {
                throw CandidateTranslationFailure.invalidRequest
            }
            output += value.substring(with: pieces.range(at: 1)) + translated
                + value.substring(with: pieces.range(at: 3)) + newline
        }
        return output
    }
}

@MainActor
private final class UnavailableSelectionTranslator: SelectionTextTranslating {
    func translate(_ text: String, target: String) async throws -> String {
        throw CandidateTranslationFailure.requiresMacOS26
    }
}

@available(macOS 26.0, *)
@MainActor
private final class AppleSelectionTranslator: SelectionTextTranslating {
    func translate(_ text: String, target: String) async throws -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let source = recognizer.dominantLanguage else { throw CandidateTranslationFailure.unsupportedLanguage }
        let sourceLanguage = Locale.Language(identifier: source.rawValue)
        let targetLanguage = Locale.Language(identifier: target)
        if sourceLanguage.languageCode == targetLanguage.languageCode { return text }
        let availability = await LanguageAvailability().status(from: sourceLanguage, to: targetLanguage)
        try Task.checkCancellation()
        guard availability == .installed else {
            throw availability == .supported ? CandidateTranslationFailure.languagePackMissing
                : CandidateTranslationFailure.unsupportedLanguage
        }
        let session = TranslationSession(installedSource: sourceLanguage, target: targetLanguage)
        return try await StructuredTextTranslation.translate(text) { line in
            try await session.translate(line).targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

@MainActor
enum SelectionTranslatorFactory {
    static func make() -> any SelectionTextTranslating {
        if #available(macOS 26.0, *) { return AppleSelectionTranslator() }
        return UnavailableSelectionTranslator()
    }
}
