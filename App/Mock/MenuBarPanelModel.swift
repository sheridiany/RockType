#if DEBUG
struct MenuBarPanelModel: Sendable {
    enum AIStatus: String, Sendable { case ready, unconfigured, error }
    struct Recent: Identifiable, Sendable {
        let id: String
        let action: SurfaceAction
        let excerpt: String
        let age: String
    }
    var ai: AIStatus
    var model: String
    var beijingTime: String?
    var beijingDate: String
    var localTime: String?
    var recent: [Recent]

    static let examples: [Recent] = [
        .init(id: "translation", action: .translate, excerpt: SurfaceSampleText.translation, age: "2 分钟"),
        .init(id: "summary", action: .summarize, excerpt: "离线编辑中的冲突与同步", age: "14 分钟"),
        .init(id: "explain", action: .explain, excerpt: "取消任务后，停止更新预览", age: "38 分钟"),
        .init(id: "polish", action: .polish, excerpt: "设计确认后安排下一轮验证", age: "1 小时"),
        .init(id: "notes", action: .summarize, excerpt: "本次讨论的三个结论", age: "2 小时"),
        .init(id: "offline", action: .translate, excerpt: "Keep working while offline.", age: "3 小时")
    ]
    static let samples: [SurfaceSample<Self>] = [
        sample("normal", "正常 · 时钟关闭"),
        sample("unconfigured", "AI 未配置", ai: .unconfigured),
        sample("empty", "最近结果为空", recent: []),
        sample("recent", "最近结果有内容", recent: examples),
        sample("clock", "北京时间 · 本地时区", clock: true),
        sample("connection-error", "AI 连接异常", ai: .error)
    ]
    private static func sample(_ id: String, _ title: String, ai: AIStatus = .ready,
                               recent: [Recent] = examples, clock: Bool = false) -> SurfaceSample<Self> {
        .init(id: id, title: title, value: .init(ai: ai, model: ai == .unconfigured ? "" : "示例模型",
            beijingTime: clock ? "16:24" : nil, beijingDate: "10 月 11 日 · 星期日",
            localTime: clock ? "旧金山 01:24" : nil, recent: recent))
    }
}

#endif
