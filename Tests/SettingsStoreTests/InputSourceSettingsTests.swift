import Testing
@testable import RoarkTApp

@MainActor @Test func inputSettingsReadsStatusWithoutOpeningAndAllowsRetry() async {
    var opens = 0
    var succeeds = false
    let manager = InputSourceManager(readSources: { .init(addedIDs: [], selectedID: nil) },
        openSettings: { opens += 1; return succeeds },
        generation: { Issue.record("Opening settings must not request input evidence"); throw TranslationServiceClient.Failure.disconnected })
    manager.refresh()
    #expect(opens == 0 && !manager.verified)
    await manager.openKeyboardSettings()
    #expect(opens == 1 && manager.settingsMessage != nil && !manager.isOpeningSettings)
    succeeds = true
    await manager.openKeyboardSettings()
    #expect(opens == 2 && manager.settingsMessage == nil && !manager.verified)
}
