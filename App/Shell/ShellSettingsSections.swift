import SwiftUI
import RoarkTCore

/// Shared production dependencies for Settings and onboarding.
@MainActor
struct ShellSettingsSections {
    let permissions: PermissionCenter
    let hotkeys: HotkeyCenter
    let showOnboarding: () -> Void

    func permissionsPane() -> AnyView { AnyView(PermissionCenterView(center: permissions)) }
    func shortcutsPane() -> AnyView { AnyView(HotkeySettingsView(center: hotkeys)) }
}

// M3-5: standalone sections bound to the single SettingsStore. The settings host owns navigation.
extension ShellSettingsSections {
    func templatesPane(settings: Binding<AppSettings>, showAIConnection: @escaping () -> Void) -> AnyView {
        AnyView(OperationTemplateSettings(settings: settings, showAIConnection: showAIConnection))
    }

    func modelsPane(settings: Binding<AppSettings>, showAIConnection: @escaping () -> Void) -> AnyView {
        AnyView(OperationModelSettings(settings: settings, showAIConnection: showAIConnection))
    }
}
