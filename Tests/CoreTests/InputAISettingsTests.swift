import Foundation
import Testing
@testable import RoarkTCore

@Test func inputAISettingsPersistThroughIMEProjectionAndMissingFieldsKeepInputPreferences() throws {
    var settings = AppSettings()
    settings.input.scheme = .flypy; settings.input.fuzzyPinyin = false
    var ai = InputAISettings(); ai.enabled = true
    ai.shortcut = Shortcut(key: "r", modifiers: [.control, .option])
    settings.input.inputAI = ai
    let encoded = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(AppSettings.self, from: encoded) == settings)
    #expect(InputMethodPreferences.decode(encoded).input.inputAI == ai)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var input = try #require(object["input"] as? [String: Any])
    input.removeValue(forKey: "inputAI"); object["input"] = input
    let withoutAI = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: withoutAI)
    #expect(decoded.input.inputAI == nil)
    #expect(decoded.input.scheme == .flypy && decoded.input.fuzzyPinyin == false)
    #expect(InputMethodPreferences.decode(withoutAI).input == decoded.input)
    #expect(InputAISettings().enabled == false)
    #expect(InputAISettings().shortcut == Shortcut(key: "tab", modifiers: .option))
    ai.shortcut = nil; settings.input.inputAI = ai
    #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)).input.inputAI?.shortcut == nil)
}
