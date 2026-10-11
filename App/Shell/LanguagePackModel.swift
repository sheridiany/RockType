import Foundation
import Observation
import Translation

@MainActor @Observable
final class LanguagePackModel {
    enum State: Equatable {
        case unchecked, checking, installed, available, unsupported, legacy, failed
        var message: String {
            switch self {
            case .unchecked: "尚未检查中英语言包。"
            case .checking: "正在检查简体中文与英文两个方向的语言包…"
            case .installed: "简体中文与英语语言包已就绪。"
            case .available: "中英翻译受支持；点击“准备语言包”后，由系统确认并下载。"
            case .unsupported: "系统暂不支持中英语言包。候选翻译可使用本地词条，其他 AI 功能需先配置连接。"
            case .legacy: "动态候选翻译需要 macOS 26。当前系统使用本地词条；输入法 AI 需配置连接并在设置中启用。"
            case .failed: "语言包准备未完成或已取消，可检查网络后重试。"
            }
        }
    }

    private(set) var state: State = .unchecked
    private var checkID = UUID()

    func refresh() async {
        let id = UUID()
        checkID = id
        guard #available(macOS 26, *) else { state = .legacy; return }
        state = .checking
        let availability = LanguageAvailability()
        let forward = await availability.status(from: .init(identifier: "zh-Hans"), to: .init(identifier: "en"))
        let reverse = await availability.status(from: .init(identifier: "en"), to: .init(identifier: "zh-Hans"))
        guard checkID == id, !Task.isCancelled else { return }
        if forward == .installed && reverse == .installed { state = .installed }
        else if forward == .unsupported || reverse == .unsupported { state = .unsupported }
        else { state = .available }
    }

    func preparationFailed() { checkID = UUID(); state = .failed }
}
