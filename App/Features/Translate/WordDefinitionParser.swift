import Foundation

/// DictionaryServices returns unstructured text, which varies by installed dictionary.
/// Recognize explicit headings only; preserve unrecognized prose without inventing metadata.
enum WordDefinitionParser {
    private static let parts = #"proper noun|plural noun|auxiliary verb|modal verb|phrasal verb|noun|verb|adjective|adverb|pronoun|preposition|conjunction|interjection|exclamation|determiner|article|abbreviation|名词|动词|形容词|副词|代词|介词|连词|感叹词|冠词|数词|adj\.|adv\.|vt\.|vi\.|prep\.|pron\.|conj\.|interj\.|n\.|v\."#
    private static let labels = ["noun": "名词", "proper noun": "专有名词", "plural noun": "复数名词",
        "verb": "动词", "auxiliary verb": "助动词", "modal verb": "情态动词", "phrasal verb": "短语动词",
        "adjective": "形容词", "adverb": "副词", "pronoun": "代词", "preposition": "介词",
        "conjunction": "连词", "interjection": "感叹词", "exclamation": "感叹词", "determiner": "限定词",
        "article": "冠词", "abbreviation": "缩写", "n.": "名词", "v.": "动词", "vt.": "及物动词",
        "vi.": "不及物动词", "adj.": "形容词", "adv.": "副词", "prep.": "介词", "pron.": "代词",
        "conj.": "连词", "interj.": "感叹词"]

    static func parse(_ raw: String, term: String) -> WordLookup.Definition? {
        guard !raw.isEmpty, raw.utf8.count <= 65_536 else { return nil }
        var body = raw.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        var pronunciation: String?
        // Pronunciation lives in the headword prefix, before the first POS heading.
        let firstPart = body.range(of: "(?i)(?<![A-Za-z])(?:" + parts + ")(?=\\s|$)", options: .regularExpression)
        let prefix = String(body[..<(firstPart?.lowerBound ?? body.index(body.startIndex, offsetBy: min(200, body.count)))])
        if let range = prefix.range(of: #"\|[^|\n]{1,100}\||/[^/\n]{1,100}/|\[[^\]\n]{1,100}\]"#, options: .regularExpression) {
            let phonetic = prefix[range].dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
            // Do not present grammatical notes such as [mass noun] as a pronunciation.
            if !phonetic.isEmpty, !phonetic.contains(":"), !phonetic.contains("noun"), !phonetic.contains("verb"),
               phonetic.range(of: #"[A-Za-z\u0250-\u02FFæɑɔθðʃʒŋāēīōūăĕĭŏŭ]"#, options: .regularExpression) != nil {
                pronunciation = "/" + phonetic + "/"
                body = String(body[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if pronunciation == nil, let range = body.range(of: NSRegularExpression.escapedPattern(for: term) + #"(?=\s|$)"#,
            options: [.anchored, .caseInsensitive, .regularExpression]) {
            body = String(body[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let end = body.range(of: #"\b(?:ORIGIN|DERIVATIVES|PHRASES|ETYMOLOGY)\b"#, options: .regularExpression) {
            body = String(body[..<end.lowerBound])
        }
        guard let headings = try? NSRegularExpression(pattern: "(?i)(?<![A-Za-z])(?:" + parts + ")(?=\\s|$)") else { return nil }
        let ns = body as NSString
        let matches = headings.matches(in: body, range: NSRange(location: 0, length: ns.length)).filter { match in
            let before = ns.substring(to: match.range.location)
            let after = ns.substring(from: NSMaxRange(match.range)).trimmingCharacters(in: .whitespaces)
            return before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || before.hasSuffix("\n")
                || after.range(of: #"^\s*(?:[1-9][0-9]?\s|\(|\[)"#, options: .regularExpression) != nil
        }
        var senses: [WordLookup.Sense] = []
        if matches.isEmpty {
            senses = meanings(body).map { .init(partOfSpeech: nil, meaning: $0) }
        } else {
            for (index, match) in matches.enumerated() {
                let start = NSMaxRange(match.range)
                let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
                let label = ns.substring(with: match.range).lowercased()
                let text = ns.substring(with: NSRange(location: start, length: end - start))
                senses += meanings(text).map { .init(partOfSpeech: labels[label] ?? label, meaning: $0) }
                if senses.count >= 3 { break }
            }
        }
        guard !senses.isEmpty else { return nil }
        return .init(term: term, pronunciation: pronunciation, senses: Array(senses.prefix(3)))
    }

    private static func meanings(_ text: String) -> [String] {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Inflection/grammar notes are metadata, not the first definition.
        while let note = text.range(of: #"^(?:\([^)]{0,180}\)|\[[^\]]{0,180}\])\s*"#, options: .regularExpression) {
            text.removeSubrange(note)
        }
        // A number in ordinary prose ("a set of 2 parts") is not a definition boundary.
        let numbered = text.range(of: #"^1[.)]?\s+"#, options: .regularExpression) != nil
        let separators = numbered ? #"(?:^|\s)[1-9][0-9]?[.)]?\s+(?=[\p{L}\[])|[•●]\s*"# : #"[•●]\s*"#
        text = text.replacingOccurrences(of: separators, with: "\n", options: .regularExpression)
        return text.components(separatedBy: .newlines).compactMap { line in
            var meaning = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let example = meaning.range(of: ": ") { meaning = String(meaning[..<example.lowerBound]) }
            guard !meaning.isEmpty else { return nil }
            return meaning.count > 260 ? String(meaning.prefix(259)) + "…" : meaning
        }.prefix(3).map { $0 }
    }
}
