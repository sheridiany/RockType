import Testing
@testable import RoarkTApp

@Test func launchOpensSettingsWithoutSetupGate() {
    #expect(SettingsLaunchPolicy.action(arguments: []) == .settings)
    #expect(SettingsLaunchPolicy.action(arguments: ["--background"]) == .none)
    #expect(SettingsLaunchPolicy.action(arguments: ["--background", "--show-settings"]) == .settings)
    for preview in ["--gallery", "--render-gallery"] {
        #expect(SettingsLaunchPolicy.action(arguments: [preview, "--show-settings"]) == .none)
    }
}
