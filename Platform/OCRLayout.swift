import Foundation

extension OCR.Result {
    public func formatted(paragraphs: Bool = false) -> String {
        let rows = Self.rows(lines)
        guard !rows.isEmpty else { return "" }
        let fragmented = rows.filter { $0.count > 1 }
        // Repeated short cells/numeric values imply a table, not newspaper columns.
        let cells = fragmented.flatMap { $0 }
        let shortCells = cells.filter { $0.text.count <= 18 }.count
        if fragmented.count >= 2, fragmented.count * 2 >= rows.count,
           shortCells * 4 >= cells.count * 3 {
            let starts = Self.columnStarts(cells)
            return rows.map { row in
                var values = Array(repeating: "", count: starts.count)
                for line in row {
                    let index = starts.indices.min { abs(starts[$0] - line.rect.minX) < abs(starts[$1] - line.rect.minX) } ?? 0
                    values[index] += (values[index].isEmpty ? "" : " ") + line.text
                }
                return values.joined(separator: "\t")
            }.joined(separator: "\n")
        }
        // A vertical gutter must extend through the complete block; don't guess across headers.
        let byX = lines.sorted { $0.rect.minX < $1.rect.minX }
        var columns: [[OCR.Line]] = []
        var right: CGFloat = -.infinity
        for line in byX {
            if columns.isEmpty || line.rect.minX > right + 0.035 {
                columns.append([line]); right = line.rect.maxX
            } else { columns[columns.count - 1].append(line); right = max(right, line.rect.maxX) }
        }
        if columns.count > 1, columns.allSatisfy({ $0.count >= 2 }) {
            return columns.map { Self.render(Self.rows($0), paragraphs: paragraphs) }.joined(separator: "\n\n")
        }
        return Self.render(rows, paragraphs: paragraphs)
    }

    private static func rows(_ lines: [OCR.Line]) -> [[OCR.Line]] {
        var rows: [[OCR.Line]] = []
        for line in lines.sorted(by: { $0.rect.midY < $1.rect.midY }) {
            if let last = rows.last?.first,
               abs(line.rect.midY - last.rect.midY) < min(line.rect.height, last.rect.height) * 0.5 {
                rows[rows.count - 1].append(line)
            } else { rows.append([line]) }
        }
        return rows.map { $0.sorted { $0.rect.minX < $1.rect.minX } }
    }
    private static func columnStarts(_ cells: [OCR.Line]) -> [CGFloat] {
        var starts: [CGFloat] = []
        for x in cells.map(\.rect.minX).sorted() {
            if let last = starts.last, x - last < 0.035 { continue }
            starts.append(x)
        }
        return starts
    }
    private static func render(_ rows: [[OCR.Line]], paragraphs: Bool) -> String {
        let lines = rows.flatMap { $0 }
        guard !lines.isEmpty else { return "" }
        let left = lines.map(\.rect.minX).min() ?? 0
        let widths = lines.filter { $0.text.count > 3 }.map { $0.rect.width / CGFloat($0.text.count) }.sorted()
        let unit = max(0.001, widths.isEmpty ? 0.01 : widths[widths.count / 2])
        let heights = lines.map(\.rect.height).sorted()
        let height = heights[heights.count / 2]
        let code = lines.filter { $0.text.contains("{") || $0.text.contains("=") || $0.text.hasPrefix("func ") || $0.text.hasPrefix("return ") }.count >= 2
        let gaps = zip(rows, rows.dropFirst()).compactMap { a, b -> CGFloat? in
            guard let first = a.first, let next = b.first else { return nil }
            return max(0, next.rect.minY - first.rect.maxY)
        }.sorted()
        let typicalGap = gaps.isEmpty ? height : gaps[gaps.count / 2]
        var output = ""
        var previous: OCR.Line?
        for row in rows {
            guard let first = row.first else { continue }
            let rawIndent = Int(((first.rect.minX - left) / unit).rounded())
            let indent = rawIndent >= 2 ? min(64, rawIndent) : 0
            let current = row.map(\.text).joined(separator: " ")
            if let previous {
                let gap = first.rect.minY - previous.rect.maxY
                let list = current.range(of: #"^(?:[-*•]|\d+[.)])\s"#, options: .regularExpression) != nil
                if gap > max(typicalGap * 1.65, height * 1.2) { output += "\n\n" }
                else if paragraphs && !code && indent == 0 && !list { output += separator(previous.text, current) }
                else { output += "\n" }
            }
            if output.isEmpty || output.hasSuffix("\n") { output += String(repeating: " ", count: indent) }
            output += current
            previous = first
        }
        return output
    }
    private static func separator(_ a: String, _ b: String) -> String {
        func cjk(_ c: Character?) -> Bool {
            c?.unicodeScalars.contains { (0x2E80...0x9FFF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) || (0xFF01...0xFF60).contains($0.value) } ?? false
        }
        return cjk(a.last) && cjk(b.first) ? "" : " "
    }
}
