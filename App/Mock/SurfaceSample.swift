#if DEBUG
// Synthetic, deterministic data for SPEC-002 surfaces 1–5. No system reads.
struct SurfaceSample<Value: Sendable>: Identifiable, Sendable {
    let id: String
    let title: String
    let value: Value
}

enum SurfaceAction: String, CaseIterable, Sendable {
    case translate, explain, summarize, search, copy, polish
    var title: String {
        switch self {
        case .translate: "翻译"
        case .explain: "解释"
        case .summarize: "总结"
        case .search: "搜索"
        case .copy: "复制"
        case .polish: "润色"
        }
    }
    var symbol: String {
        switch self {
        case .translate: "character.bubble"
        case .explain: "text.bubble"
        case .summarize: "list.bullet"
        case .search: "magnifyingglass"
        case .copy: "doc.on.doc"
        case .polish: "pencil.line"
        }
    }
}

enum SurfaceSampleText {
    static let original = "Local-first tools keep the main copy of your data on your device. You can keep working offline and sync your changes later."
    static let translation = "本地优先的工具把数据的主副本保存在你的设备上。即使离线，你也能继续工作，之后再同步修改。"
    static let summary = "• 数据主副本保存在本机。\n• 离线时仍然可以编辑。\n• 联网后同步，并保留冲突副本。"
    static let question = "本地优先和离线优先有什么区别？"
    static let answer = "离线优先关注断网时是否可用；本地优先还关注数据归属，让设备上的主副本不依赖服务持续运行。"
    static let code = "let task = Task {\n    try await loadPreview()\n}\ntask.cancel()"
    static let long = Array(repeating: "协作时，两台设备可能同时修改一份笔记。工具需要保留双方的修改，并说明冲突发生的位置。同步状态应当清楚，离线时也不应阻止继续编辑。", count: 12).joined(separator: "\n\n")
    static let imageLines = ["Preview — synthetic example", "Error: preview service is already running", "Stop the previous preview and try again."]
    static let ocr = imageLines.joined(separator: "\n")
}

#endif
