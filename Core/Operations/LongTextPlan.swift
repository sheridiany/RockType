import Foundation

/// UTF-8 budgets, independent of provider tokenizers. Content stays in memory.
public enum LongTextPlan {
    public static let maximumBytes = 262_144
    public static let segmentBytes = 8_192
    public static let maximumSegments = 64
    public static let concurrency = 2
    public static let guidance = "翻译与总结支持最多 256 KiB；按段落分段，最多两段并行。单个代码块最多 8 KiB，超长普通段落会继续细分。"

    public static func split(_ text: String, budget: Int) throws -> [String] {
        guard text.utf8.count <= maximumBytes else { throw OperationFailure.inputTooLong(limit: maximumBytes) }
        let limit = min(segmentBytes, budget)
        guard limit > 0 else { throw OperationFailure.inputTooLong(limit: max(0, budget)) }
        let regex = try NSRegularExpression(pattern: "[^\\r\\n]*(?:\\r\\n|\\r|\\n)|[^\\r\\n]+$")
        let ns = text as NSString
        var blocks: [(String, Bool)] = [], block = ""
        var fence: (Character, Int)?
        var indented = false
        func flush(_ code: Bool = false) {
            if !block.isEmpty { blocks.append((block, code)); block = "" }
        }
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let line = ns.substring(with: match.range)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let first = trimmed.first
            let count = (first == "`" || first == "~") ? trimmed.prefix { $0 == first }.count : 0
            if let active = fence {
                block += line
                if first == active.0, count >= active.1,
                   trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty {
                    fence = nil; flush(true)
                }
            } else if count >= 3, let first {
                flush(indented); indented = false; fence = (first, count); block = line
            } else {
                let isList = trimmed.range(of: "^(?:[-*+]|[0-9]+[.)])[ \t]+", options: .regularExpression) != nil
                let isIndented = !isList && (line.hasPrefix("    ") || line.hasPrefix("\t"))
                if indented && !isIndented && !trimmed.isEmpty { flush(true); indented = false }
                if isIndented && !indented { flush(); indented = true }
                block += line
                if trimmed.isEmpty && !indented { flush() }
            }
        }
        flush(fence != nil || indented)
        var chunks: [String] = [], pending = "", bytes = 0
        func append(_ value: String) {
            let size = value.utf8.count
            if bytes + size > limit, !pending.isEmpty { chunks.append(pending); pending = ""; bytes = 0 }
            pending += value; bytes += size
        }
        for (value, code) in blocks {
            if code && value.utf8.count > limit { throw OperationFailure.codeBlockTooLong(limit: limit) }
            if value.utf8.count <= limit { append(value); continue }
            // Oversized prose prefers whitespace/punctuation, then whole graphemes; bytes are never dropped.
            var part = "", size = 0
            for character in value {
                let width = String(character).utf8.count
                guard width <= limit else { throw OperationFailure.inputTooLong(limit: limit) }
                if size + width > limit {
                    if let boundary = part.lastIndex(where: { $0.isWhitespace || ".!?。！？；;".contains($0) }) {
                        let end = part.index(after: boundary)
                        let prefix = String(part[..<end])
                        if prefix.utf8.count >= limit / 2 {
                            append(prefix); part = String(part[end...]); size = part.utf8.count
                        }
                    }
                    if size + width > limit { append(part); part = ""; size = 0 }
                }
                part.append(character); size += width
            }
            if !part.isEmpty { append(part) }
        }
        if !pending.isEmpty { chunks.append(pending) }
        guard chunks.count <= maximumSegments else { throw OperationFailure.tooManySegments(limit: maximumSegments) }
        return chunks
    }

    /// Runs a bounded number of child operations; completion order never changes document order.
    @MainActor static func ordered(_ parts: [String],
        operation: @escaping @MainActor @Sendable (Int, String) async throws -> OperationResult,
        ready: @MainActor (Int, OperationResult) throws -> Void) async throws -> [OperationResult] {
        try await withThrowingTaskGroup(of: (Int, OperationResult).self) { group in
            defer { group.cancelAll() }
            var scheduled = 0, emitted = 0
            var results = [OperationResult?](repeating: nil, count: parts.count)
            func submit(_ index: Int) { group.addTask { (index, try await operation(index, parts[index])) } }
            while scheduled < min(concurrency, parts.count) { submit(scheduled); scheduled += 1 }
            while let (index, result) = try await group.next() {
                try Task.checkCancellation()
                results[index] = result
                while emitted < results.count, let next = results[emitted] { try ready(emitted, next); emitted += 1 }
                if scheduled < parts.count { submit(scheduled); scheduled += 1 }
            }
            return results.compactMap { $0 }
        }
    }
}
