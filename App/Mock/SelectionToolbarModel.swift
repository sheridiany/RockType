#if DEBUG
struct SelectionToolbarModel: Sendable {
    enum State: String, CaseIterable, Sendable {
        case normal, compact, copied, unconfigured, secureInput
        var title: String {
            switch self {
            case .normal: "普通"
            case .compact: "紧凑"
            case .copied: "已复制"
            case .unconfigured: "AI 未配置"
            case .secureInput: "安全输入 · 隐藏工具栏"
            }
        }
    }
    var state: State
    var actions: [SurfaceAction]
    var compact: Bool { state == .compact }
    var isVisible: Bool { state != .secureInput }
    func disabledReason(for action: SurfaceAction) -> String? {
        guard state == .unconfigured, [.explain, .summarize, .polish].contains(action) else { return nil }
        return "需要配置 AI"
    }
    static let samples: [SurfaceSample<Self>] = State.allCases.map {
        .init(id: $0.rawValue, title: $0.title, value: .init(state: $0,
            actions: $0 == .secureInput ? [] : [.translate, .explain, .summarize, .search, .copy]))
    }
}

#endif
