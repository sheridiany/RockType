import Foundation
import NaturalLanguage

// Text travels only through private process pipes, never arguments or logs.
let data = FileHandle.standardInput.readDataToEndOfFile()
guard let original = String(data: data, encoding: .utf8),
      let text = original.applyingTransform(StringTransform("Hant-Hans"), reverse: false)
else { exit(1) }
let tokenizer = NLTokenizer(unit: .word)
tokenizer.setLanguage(.simplifiedChinese)
tokenizer.string = text
var words: [String] = []
tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
    let word = String(text[range])
    if word.range(of: "^[\\p{Han}]{2,16}$", options: .regularExpression) != nil {
        words.append(word)
    }
    return true
}
FileHandle.standardOutput.write(try JSONEncoder().encode(words))
