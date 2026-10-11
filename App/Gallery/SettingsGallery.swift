#if DEBUG
import SwiftUI

@MainActor
enum SettingsGallery {
    static let entries: [GalleryEntry] = SettingsFixtures.all.map { model in
        let id = model.section.rawValue + "-" + model.scenario.rawValue
        return GalleryEntry(surface: "settings", state: id, title: "设置 · " + model.section.title + " · " + title(model.scenario)) {
            AnyView(SettingsView(model: model).id(id))
        }
    }
    private static func title(_ scenario: SettingsPresentation.Scenario) -> String {
        switch scenario {
        case .normal: "默认"
        case .unconfigured: "AI 未配置"
        case .testing: "连接测试中"
        case .mixed: "连接测试混合结果"
        case .conflict: "快捷键冲突"
        case .denied: "权限未授权"
        case .downloading: "语音模型下载中"
        case .edited: "模板编辑"
        case .actions: "功能与应用"
        case .installed: "语音模型已就绪"
        }
    }
}

#endif
