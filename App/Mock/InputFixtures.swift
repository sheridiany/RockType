import SwiftUI

struct CandidatePresentation {
    enum State: String, CaseIterable {
        case none, translating, chineseEnglish = "zh-en", englishChinese = "en-zh"
        case dictionary, unavailable, ai, long
        var title: String {
            switch self {
            case .none: "无译文"
            case .translating: "翻译中"
            case .chineseEnglish: "中→英译文"
            case .englishChinese: "英→中释义"
            case .dictionary: "静态词条"
            case .unavailable: "不可用"
            case .ai: "AI 改写结果"
            case .long: "长译文截断"
            }
        }
    }
    let state: State
    let preedit: String
    let candidates: [String]
    let translation: String
    let source: String
    var selectedIndex = 0
    var canCommit: Bool { ![.none, .translating, .unavailable].contains(state) }
}

enum InputFixtures {
    static func candidate(_ state: CandidatePresentation.State) -> CandidatePresentation {
        let english = state == .englishChinese
        let text: String = switch state {
        case .none: ""
        case .translating: "正在翻译…"
        case .chineseEnglish: "Good morning"
        case .englishChinese: "早晨；上午"
        case .dictionary: "Good morning"
        case .unavailable: "暂无可用译文 · 静态词条未命中"
        case .ai: "Wishing you a wonderful morning."
        case .long: "Good morning. May this quiet beginning bring you fresh ideas, a clear mind, and enough time to enjoy every small moment of the day."
        }
        return CandidatePresentation(state: state, preedit: english ? "morning" : "zao shang hao",
            candidates: english ? ["morning", "morn", "more", "mourn", "modern"] : ["早上好", "早上", "早", "找", "照"],
            translation: text,
            source: state == .dictionary ? "静态词条" : state == .ai ? "AI 改写" : "候选翻译")
    }
}

enum InputModePresentation: String, CaseIterable {
    case chinese, english, scheme
    var title: String {
        switch self { case .chinese: "中文输入"; case .english: "英文输入"; case .scheme: "切换方案" }
    }
    var badge: String { self == .english ? "英" : "中" }
    var detail: String { self == .scheme ? "小鹤双拼" : title }
}
