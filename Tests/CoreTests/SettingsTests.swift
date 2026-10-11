import Foundation
import Testing
@testable import RoarkTCore

@Test func settingsDefaultsRespectPrivacyAndProductChoices() throws {
    let settings = AppSettings()
    #expect(settings.schemaVersion == 1)
    #expect(!settings.general.showBeijingTime && !settings.general.launchAtLogin)
    #expect(!settings.general.onboardingCompleted)
    #expect(!settings.translation.allowCandidateAI)
    #expect(!settings.voice.polishWithAI && !settings.voice.automaticallyPrepareModel)
    #expect(settings.voice.model == .small)
    #expect(settings.selection.excludedApplications == ["com.apple.finder"])
    #expect(settings.shortcuts.bindings == Shortcut.defaults)
    #expect(settings.shortcuts.inputMethodAI == nil && settings.shortcuts.showSettings == nil)
    #expect(Set(settings.templates.map(\.id)) == Set(["translate", "summarize", "polish", "explain"]))
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(AppSettings.self, from: data) == settings)
    let json = String(decoding: data, as: UTF8.self)
    #expect(!json.contains("apiKey") && !json.contains("hasAPIKey"))
}

@Test func editedSettingsRoundTripWithoutLosingChoices() throws {
    var settings = AppSettings()
    settings.general.showBeijingTime = true
    settings.input.scheme = .flypy
    settings.translation.targetLanguage = "ja"
    settings.voice.model = .large
    settings.selection.toolbarActions.reverse()
    settings.screenshot.format = .jpeg
    settings.ai.defaultModel = "test-model"
    settings.templates[0].prompt = "Test template"
    settings.shortcuts.bindings[.screenshot] = nil
    settings.privacy.keepRecentResultsInMemory = false
    #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)) == settings)
    #expect(AppSettings.defaults.templates == OperationTemplate.defaults)
}
