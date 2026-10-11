import Foundation
import NaturalLanguage

// Text and bounded contexts travel only through private pipes, never logs.
let data = FileHandle.standardInput.readDataToEndOfFile()
guard let original = String(data: data, encoding: .utf8),
      let text = original.applyingTransform(StringTransform("Hant-Hans"), reverse: false)
else { exit(1) }
let tokenizer = NLTokenizer(unit: .word)
tokenizer.setLanguage(.simplifiedChinese)
tokenizer.string = text
struct Token: Encodable {
    let word: String
    let left: String
    let right: String
}
var words: [Token] = []
tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
    let word = String(text[range])
    if word.range(of: "^[\\p{Han}]{2,16}$", options: .regularExpression) != nil {
        let start = text.index(range.lowerBound, offsetBy: -15, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 15, limitedBy: text.endIndex) ?? text.endIndex
        let prefix = String(text[start..<range.lowerBound])
        let suffix = String(text[range.upperBound..<end])
        let left = prefix.range(of: "[\\p{Han}]*$", options: .regularExpression).map { String(prefix[$0]) } ?? ""
        let right = suffix.range(of: "^[\\p{Han}]*", options: .regularExpression).map { String(suffix[$0]) } ?? ""
        words.append(Token(word: word, left: left, right: right))
    }
    return true
}
FileHandle.standardOutput.write(try JSONEncoder().encode(words))
