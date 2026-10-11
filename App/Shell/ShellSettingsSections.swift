import SwiftUI

/// Shared production dependencies for Settings and onboarding.
@MainActor
struct ShellSettingsSections {
    let permissions: PermissionCenter
    let hotkeys: HotkeyCenter
    let showOnboarding: () -> Void

    func permissionsPane() -> AnyView { AnyView(PermissionCenterView(center: permissions)) }
    func shortcutsPane() -> AnyView { AnyView(HotkeySettingsView(center: hotkeys)) }
}
