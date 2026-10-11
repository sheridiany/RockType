import AppKit
import Observation
import ServiceManagement
import RoarkTCore

@MainActor @Observable
final class LoginItemController {
    private(set) var enabled = false
    private(set) var requiresApproval = false
    private(set) var message = ""

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled
        requiresApproval = status == .requiresApproval
        switch status {
        case .enabled: message = "登录后在菜单栏常驻"
        case .notRegistered: message = "未启用开机启动"
        case .requiresApproval: message = "请在系统设置 → 通用 → 登录项中允许 RoarkT"
        case .notFound: message = "请从已安装的 RoarkT.app 中设置开机启动"
        @unknown default: message = "无法确认开机启动状态"
        }
    }

    /// The caller persists the returned system state, never an optimistic switch value.
    @discardableResult
    func setEnabled(_ requested: Bool) -> Bool {
        do {
            if requested { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refresh()
        } catch {
            refresh()
            message = "开机启动设置未完成，请检查系统登录项后重试。"
        }
        let succeeded = enabled == requested && !requiresApproval
        Task {
            try? await DiagnosticLog.shared.record(.init(action: .launchAtLogin,
                status: succeeded ? .succeeded : .unavailable))
        }
        return enabled
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
