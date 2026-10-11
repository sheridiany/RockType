import SwiftUI

/// S3 supplies these two panes; S4 supplies the onboarding action at composition time.
/// Defaults explicitly report missing integration instead of showing simulated authorization.
@MainActor
protocol ShellSettingsSections {
    func permissionsPane() -> AnyView
    func shortcutsPane() -> AnyView
    func showOnboarding()
}

struct PendingShellSettingsSections: ShellSettingsSections {
    func permissionsPane() -> AnyView {
        AnyView(Notice(text: "权限中心等待集成。普通输入无需授权；各功能将在使用时说明用途并单独请求权限。"))
    }
    func shortcutsPane() -> AnyView {
        AnyView(Notice(text: "全局快捷键等待集成，当前没有通过此界面注册快捷键。截图与语音功能即将推出。"))
    }
    func showOnboarding() {
        let alert = NSAlert()
        alert.messageText = "首次引导等待集成"
        alert.informativeText = "输入源、语言包与按需授权的真实检查由首次引导提供。"
        alert.runModal()
    }
}
