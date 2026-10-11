struct ResultWindowModel: Sendable {
    enum State: String, CaseIterable, Sendable {
        case connecting, streaming, done, followup, interrupted, truncated, cancelled
        case networkError, authenticationError, inputTooLong, longContent, code, sourceGone, copyFallback, summary
        var title: String {
            switch self {
            case .connecting: "连接中"
            case .streaming: "流式中"
            case .done: "完成"
            case .followup: "追问中"
            case .interrupted: "不完整 · 断流"
            case .truncated: "不完整 · 被截断"
            case .cancelled: "已取消"
            case .networkError: "错误 · 网络"
            case .authenticationError: "错误 · 认证"
            case .inputTooLong: "错误 · 输入过长"
            case .longContent: "长内容"
            case .code: "代码内容"
            case .sourceGone: "返回来源失败"
            case .copyFallback: "复制回退取词"
            case .summary: "总结 · 要点"
            }
        }
    }
    enum Phase: Sendable { case connecting, streaming, done, incomplete, cancelled, error }
    struct Turn: Identifiable, Sendable {
        let id: String
        var question: String?
        var answer: String
        var code: String?
        var phase: Phase
    }
    var state: State
    var action: SurfaceAction
    var sourceApp: String
    var captureMethod: String
    var original: String
    var model: String
    var targetLanguage: String?
    var turns: [Turn]
    var notice: String?
    var recovery: String?
    var elapsed: String
    var sourceAvailable: Bool
    var isBusy: Bool { turns.last.map { $0.phase == .connecting || $0.phase == .streaming } ?? false }
    var hasAnswer: Bool { turns.contains { !$0.answer.isEmpty } }

    static let samples: [SurfaceSample<Self>] = State.allCases.map {
        .init(id: $0.rawValue, title: $0.title, value: sample($0))
    }
    static func sample(_ state: State) -> Self {
        var value = Self(state: state, action: .translate, sourceApp: "示例文稿", captureMethod: "直接读取",
            original: SurfaceSampleText.original, model: "示例模型", targetLanguage: "中文",
            turns: [.init(id: "answer", answer: SurfaceSampleText.translation, phase: .done)],
            elapsed: "1.8 秒", sourceAvailable: true)
        switch state {
        case .connecting:
            value.turns[0].answer = ""; value.turns[0].phase = .connecting; value.elapsed = "等待响应"
        case .streaming:
            value.turns[0].answer = String(SurfaceSampleText.translation.prefix(28))
            value.turns[0].phase = .streaming; value.elapsed = "首字 0.4 秒"
        case .followup:
            value.action = .summarize; value.targetLanguage = nil
            value.turns[0].answer = SurfaceSampleText.summary
            value.turns.append(.init(id: "followup", question: SurfaceSampleText.question,
                answer: String(SurfaceSampleText.answer.prefix(30)), phase: .streaming))
        case .interrupted, .truncated:
            value.turns[0].answer = String(SurfaceSampleText.translation.prefix(35))
            value.turns[0].phase = .incomplete
            value.notice = state == .interrupted ? "连接在完成前中断，以上只是部分译文。" : "输出达到长度上限，以上内容不完整。"
            value.recovery = "重试"
        case .cancelled:
            value.turns[0].answer = String(SurfaceSampleText.translation.prefix(24))
            value.turns[0].phase = .cancelled; value.notice = "已停止，保留已生成的部分结果。"
        case .networkError, .authenticationError, .inputTooLong:
            value.turns[0].answer = ""; value.turns[0].phase = .error
            switch state {
            case .networkError:
                value.notice = "无法连接到服务。请检查网络后重试。"; value.recovery = "重试"
            case .authenticationError:
                value.notice = "当前密钥无效或没有权限（401）。请在 AI 连接中更新。"; value.recovery = "打开 AI 连接"
            default:
                value.notice = "内容超出模型输入上限。请缩短选区后重试，不会自动截断。"
                value.recovery = "重新选择内容"
            }
            value.elapsed = "未完成"
        case .longContent:
            value.action = .summarize; value.targetLanguage = nil
            value.original = SurfaceSampleText.long; value.turns[0].answer = SurfaceSampleText.long
        case .code:
            value.action = .explain; value.targetLanguage = nil; value.original = SurfaceSampleText.code
            value.turns[0].answer = "取消会向任务发出信号。任务应主动检查取消状态，并停止更新结果。"
            value.turns[0].code = SurfaceSampleText.code
        case .sourceGone:
            value.sourceAvailable = false; value.notice = "来源窗口已关闭。结果已复制，可粘贴到其他位置。"
        case .copyFallback: value.captureMethod = "复制回退"
        case .summary:
            value.action = .summarize; value.targetLanguage = nil; value.turns[0].answer = SurfaceSampleText.summary
        case .done: break
        }
        return value
    }
}
