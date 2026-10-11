import Foundation

/// Conservative local dictation cleanup; ambiguous words without punctuation stay intact.
public enum VoiceTextCleaner {
    public static func clean(_ text: String) -> String {
        var result = text.replacingOccurrences(of: #"[^\S\r\n]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Only complete punctuation-delimited interjections, never prefixes of real words.
        let filler = #"(^|[，,。！？!?；;\n]) *(?:嗯|啊|呃|额|那个|就是说) *(?:[，,。！？!?；;]+ *|$)"#
        while true {
            let next = result.replacingOccurrences(of: filler, with: "$1", options: .regularExpression)
            if next == result { break }
            result = next
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        // A Han character at the end needs a stop. Existing punctuation/quotes stay untouched.
        if let last = result.unicodeScalars.last, CharacterSet.letters.contains(last),
           result.range(of: #"\p{Han}$"#, options: .regularExpression) != nil {
            result += "。"
        }
        return result
    }
}
