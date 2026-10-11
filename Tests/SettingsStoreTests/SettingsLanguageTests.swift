import Testing
@testable import RoarkTApp

@Test func languageChoicesPreserveUnknownValuesAndLastSelection() {
    let original = ["zh-Hans", "en-US", "fr-FR"]
    #expect(SettingsOCRLanguages.setting("en-US", enabled: false, in: original) == ["zh-Hans", "fr-FR"])
    #expect(SettingsOCRLanguages.setting("zh-Hans", enabled: true, in: original) == original)
    #expect(SettingsOCRLanguages.setting("ja-JP", enabled: true, in: original) == original + ["ja-JP"])
    #expect(SettingsOCRLanguages.setting("zh-Hans", enabled: false, in: ["zh-Hans"]) == ["zh-Hans"])
    #expect(SettingsOCRLanguages.setting("en-US", enabled: true, in: []) == ["en-US"])
}
