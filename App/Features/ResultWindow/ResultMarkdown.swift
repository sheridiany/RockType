import SwiftUI

struct ResultMarkdown {
    struct Block: Equatable {
        enum Kind: Equatable { case prose, heading(Int), code(String) }
        var kind: Kind
        var text: String
    }
    /// Fences may be unfinished while streaming; their content is still code, never an instruction.
    static func blocks(_ source: String) -> [Block] {
        var result: [Block] = [], prose: [String] = [], code: [String] = []
        var fence: (Character, Int, String)?
        func flush() {
            if !prose.isEmpty { result.append(Block(kind: .prose, text: prose.joined(separator: "\n"))); prose = [] }
        }
        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let marker = trimmed.first ?? " "
            let count = (marker == "`" || marker == "~") ? trimmed.prefix(while: { $0 == marker }).count : 0
            if let active = fence {
                if marker == active.0, count >= active.1, trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty {
                    result.append(Block(kind: .code(active.2), text: code.joined(separator: "\n")))
                    fence = nil; code = []
                } else { code.append(line) }
            } else if count >= 3 {
                flush(); fence = (marker, count, String(trimmed.dropFirst(count)).trimmingCharacters(in: .whitespaces))
            } else {
                let hashes = line.prefix(while: { $0 == "#" }).count
                if (1...6).contains(hashes), line.dropFirst(hashes).first == " " {
                    flush(); result.append(Block(kind: .heading(hashes), text: String(line.dropFirst(hashes + 1))))
                } else if line.isEmpty { flush() }
                else { prose.append(line) }
            }
        }
        if let active = fence { result.append(Block(kind: .code(active.2), text: code.joined(separator: "\n"))) }
        flush()
        return result
    }
    static func inline(_ text: String) -> AttributedString {
        var value = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        // Never let generated links open files, custom schemes or execute actions.
        for run in value.runs {
            if let url = run.link, !["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                value[run.range].link = nil
            }
        }
        return value
    }
}

struct ResultAnswerView: View {
    let text: String
    let markdown: Bool
    let copyCode: (String) -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            if !markdown {
                Text(text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(ResultMarkdown.blocks(text).enumerated()), id: \.offset) { _, block in
                    switch block.kind {
                    case .prose:
                        Text(ResultMarkdown.inline(block.text)).textSelection(.enabled)
                            .lineSpacing(Tokens.Typography.readingSpacing).fixedSize(horizontal: false, vertical: true)
                    case .heading(let level):
                        Text(ResultMarkdown.inline(block.text)).font(.system(size: level == 1 ? 20 : 17, weight: .semibold))
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    case .code(let language):
                        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
                            HStack {
                                Text(language.isEmpty ? "代码" : String(language.prefix(40)))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                Spacer()
                                Button("复制代码") { copyCode(block.text) }.buttonStyle(DesignButtonStyle(variant: .ghost))
                            }
                            ScrollView(.horizontal) {
                                Text(block.text).font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled).fixedSize(horizontal: true, vertical: true)
                            }
                        }.padding(Tokens.Space.sm)
                            .background(Tokens.palette(scheme).bubble, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                    }
                }
            }
        }.font(Tokens.Typography.font(Tokens.Typography.read))
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                ["http", "https"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
            })
    }
}
