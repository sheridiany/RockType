import SwiftUI
import RoarkTCore

/// Production dependencies for the settings window.
@MainActor
struct ShellSettingsSections {
    let permissions: PermissionCenter
    let hotkeys: HotkeyCenter

    func permissionsPane() -> AnyView { AnyView(PermissionCenterView(center: permissions)) }
    func shortcutsPane(settings: Binding<AppSettings>) -> AnyView { AnyView(HotkeySettingsView(center: hotkeys, appSettings: settings)) }
}

// M3-5: standalone sections bound to the single SettingsStore. The settings host owns navigation.
extension ShellSettingsSections {
    func templatesPane(settings: Binding<AppSettings>, showAIConnection: @escaping () -> Void) -> AnyView {
        AnyView(OperationTemplateSettings(settings: settings, showAIConnection: showAIConnection, hotkeys: hotkeys))
    }

    func modelsPane(settings: Binding<AppSettings>, showAIConnection: @escaping () -> Void) -> AnyView {
        AnyView(OperationModelSettings(settings: settings, showAIConnection: showAIConnection))
    }
}
