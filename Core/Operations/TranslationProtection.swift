import Foundation

/// Only selected literals leave the model's translation scope; originals stay in memory.
struct TranslationProtection: Sendable {
    let text: String
    let prefix: String
    let literals: [String: String]
    init(_ source: String) throws {
        let ns = source as NSString
        let whole = NSRange(location: 0, length: ns.length)
        var ranges: [NSRange] = []
        let openings = try NSRegularExpression(pattern: "(?m)^[ \\t]{0,3}(`{3,}|~{3,})[^\\r\\n]*(?:\\r?\\n|$)")
        var consumed = 0
        for match in openings.matches(in: source, range: whole) where match.range.location >= consumed {
            let delimiter = ns.substring(with: match.range(at: 1))
            let character = String(delimiter.prefix(1))
            let closing = try NSRegularExpression(pattern: "(?m)^[ \\t]{0,3}" + NSRegularExpression.escapedPattern(for: character)
                + "{\(delimiter.count),}[ \\t]*(?:\\r?\\n|$)")
            let endStart = NSMaxRange(match.range)
            let end = closing.firstMatch(in: source, range: NSRange(location: endStart, length: ns.length - endStart)).map { NSMaxRange($0.range) } ?? ns.length
            ranges.append(NSRange(location: match.range.location, length: end - match.range.location)); consumed = end
        }
        let indented = try NSRegularExpression(pattern: "(?m)^(?: {4}|\\t)[^\\r\\n]*(?:\\r?\\n|$)")
        for match in indented.matches(in: source, range: whole) {
            let line = ns.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            let isList = line.range(of: "^(?:[-*+]|[0-9]+[.)])[ \t]+", options: .regularExpression) != nil
            if !isList, !ranges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) { ranges.append(match.range) }
        }
        for pattern in ["(?<!`)(`+)(?!`)[^\\r\\n]*?(?<!`)\\1(?!`)", "(?<![A-Za-z0-9+.-])(?:[A-Za-z][A-Za-z0-9+.-]{0,31}://|mailto:|www\\.)[^\\s<>\"`]+"] {
            for match in try NSRegularExpression(pattern: pattern).matches(in: source, range: whole) {
                guard !ranges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { continue }
                var range = match.range
                if pattern.contains("mailto") {
                    var characters = Array(ns.substring(with: range))
                    var parentheses = characters.reduce(0) { $0 + ($1 == "(" ? 1 : $1 == ")" ? -1 : 0) }
                    var brackets = characters.reduce(0) { $0 + ($1 == "[" ? 1 : $1 == "]" ? -1 : 0) }
                    while let last = characters.last, ".,;:!?。，；：！？".contains(last)
                        || (last == ")" && parentheses < 0) || (last == "]" && brackets < 0) {
                        characters.removeLast()
                        if last == ")" { parentheses += 1 }
                        if last == "]" { brackets += 1 }
                    }
                    range.length = String(characters).utf16.count
                }
                if range.length > 0 { ranges.append(range) }
            }
        }
        guard ranges.count <= 512 else { throw OperationFailure.unavailable }
        prefix = "⟦RT_" + UUID().uuidString.replacingOccurrences(of: "-", with: "") + "_"
        var literals: [String: String] = [:]
        let output = NSMutableString(string: source)
        for (index, range) in ranges.sorted(by: { $0.location < $1.location }).enumerated().reversed() {
            let marker = prefix + String(index) + "⟧"
            literals[marker] = ns.substring(with: range)
            output.replaceCharacters(in: range, with: marker)
        }
        self.text = output as String; self.literals = literals
    }
    func restore(_ answer: String) throws -> String {
        var stream = Stream(protection: self)
        let value = try stream.append(answer)
        guard stream.pending.isEmpty, stream.seen.count == literals.count else { throw OperationFailure.unavailable }
        return value
    }
    struct Stream {
        let protection: TranslationProtection
        init(protection: TranslationProtection) { self.protection = protection }
        fileprivate var pending = ""
        fileprivate var seen = Set<String>()
        mutating func append(_ delta: String) throws -> String {
            pending += delta
            var output = ""
            while !pending.isEmpty {
                if let start = pending.range(of: protection.prefix) {
                    output += pending[..<start.lowerBound]
                    pending.removeSubrange(pending.startIndex..<start.lowerBound)
                    let header = pending.prefix(protection.prefix.count + 12)
                    guard let end = header.firstIndex(of: "⟧") else {
                        guard pending.count < protection.prefix.count + 12 else { throw OperationFailure.unavailable }
                        break
                    }
                    let marker = String(pending[...end])
                    guard let literal = protection.literals[marker], seen.insert(marker).inserted else { throw OperationFailure.unavailable }
                    output += literal; pending.removeSubrange(pending.startIndex...end)
                } else {
                    var retained = 0
                    for count in 1...min(pending.count, protection.prefix.count) {
                        if protection.prefix.hasPrefix(pending.suffix(count)) { retained = count }
                    }
                    output += pending.dropLast(retained)
                    pending = String(pending.suffix(retained))
                    break
                }
            }
            return output
        }
    }
}
