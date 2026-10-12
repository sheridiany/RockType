import Foundation
import Testing
@testable import RoarkTCore

@Test func inputMethodReadsOnlyItsPreferencesAndDefaultsWithoutWriting() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let url = directory.appendingPathComponent("settings.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(InputMethodPreferences.load(from: url) == .defaults)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var settings = AppSettings()
    settings.input.candidateTranslation = false
    settings.input.scheme = .flypy
    settings.input.showModeIndicator = false
    settings.translation.allowCandidateAI = true
    settings.translation.targetLanguage = "en"
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
    // Invalid unrelated fields must neither be interpreted nor make IME preferences unusable.
    object["ai"] = 42
    object["voice"] = false
    let good = try JSONSerialization.data(withJSONObject: object)
    try good.write(to: url)
    #expect(InputMethodPreferences.load(from: url) == InputMethodPreferences(input: settings.input, translation: settings.translation))
    for bad in [Data("broken".utf8), Data("{\"schemaVersion\":99}".utf8), Data("{\"schemaVersion\":1,\"input\":{\"scheme\":\"unknown\"}}".utf8)] {
        try bad.write(to: url)
        #expect(InputMethodPreferences.load(from: url) == .defaults)
        #expect(try Data(contentsOf: url) == bad)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["settings.json"])
    }
    #expect(InputMethodPreferences.decode(Data("{\"schemaVersion\":1}".utf8)) == .defaults)
}

@Test func rimePatchesToggleOnlyOptionalRulesAndKeepEncodingIntact() {
    var settings = InputSettings()
    for scheme in [InputSettings.Scheme.pinyin, .flypy] {
        let defaults = RimeSettingsPatch.yaml(for: scheme, settings: settings)
        #expect(defaults.hasPrefix(RimeSettingsPatch.marker + "\npatch:\n"))
        #expect(!defaults.contains("speller/algebra"), "Defaults must inherit the shipped algebra")
    }
    settings.fuzzyPinyin = false; settings.abbreviatedPinyin = false; settings.spellingCorrection = false
    settings.shiftTogglesLanguage = false; settings.englishCompletion = false
    let pinyin = RimeSettingsPatch.yaml(for: .pinyin, settings: settings)
    let flypy = RimeSettingsPatch.yaml(for: .flypy, settings: settings)
    #expect(pinyin.contains("\"ascii_composer/switch_key/Shift_L\": noop"))
    #expect(pinyin.contains("\"english/enable_completion\": false"))
    #expect(pinyin.components(separatedBy: "speller/algebra/@").count - 1 == 18)
    #expect(flypy.components(separatedBy: "speller/algebra/@").count - 1 == 6)
    #expect(!flypy.contains("@0\"") && !flypy.contains("@7\""), "Keep erase and double-pinyin encoding rules unchanged")
    #expect(!flypy.contains("translator/enable_correction"), "Pinyin correction does not change double-pinyin encoding")
}

@Test func rimeWriterPreservesUserFilesAndIsIdempotent() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = RimeSettingsPatchWriter(directory: directory)
    let first = try writer.write(InputSettings())
    #expect(first.changed && first.conflicts.isEmpty)
    #expect(try writer.write(InputSettings()).changed == false)
    let pinyin = directory.appendingPathComponent("roarkt.custom.yaml")
    let flypy = directory.appendingPathComponent("roarkt_flypy.custom.yaml")
    let originalPinyin = try Data(contentsOf: pinyin)
    let originalDate = try #require(FileManager.default.attributesOfItem(atPath: pinyin.path)[.modificationDate] as? Date)
    let userFile = Data("# user config\npatch:\n  menu/page_size: 3\n".utf8)
    try userFile.write(to: flypy)
    var changed = InputSettings(); changed.fuzzyPinyin = false
    let conflict = try writer.write(changed)
    #expect(!conflict.changed && conflict.conflicts == ["roarkt_flypy.custom.yaml"])
    #expect(try Data(contentsOf: flypy) == userFile)
    #expect(try Data(contentsOf: pinyin) == originalPinyin, "Conflict must not partially update the other schema")
    try FileManager.default.removeItem(at: flypy)
    #expect(try writer.write(changed).changed)
    #expect(try String(contentsOf: pinyin, encoding: .utf8).contains("speller/algebra/@0"))
    #expect(try writer.write(InputSettings()).changed)
    #expect(try Data(contentsOf: pinyin) == originalPinyin)
    let restoredDate = try #require(FileManager.default.attributesOfItem(atPath: pinyin.path)[.modificationDate] as? Date)
    #expect(floor(restoredDate.timeIntervalSince1970) >= floor(originalDate.timeIntervalSince1970) + 2,
            "Each generated revision must invalidate librime's second-resolution timestamp cache")
}

@Test func rimeWriterDoesNotFollowSymlinkOrAcceptMarkerInBody() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let target = directory.appendingPathComponent("target.yaml")
    let data = Data(RimeSettingsPatch.yaml(for: .pinyin, settings: .init()).utf8)
    try data.write(to: target)
    let link = directory.appendingPathComponent("roarkt.custom.yaml")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    let writer = RimeSettingsPatchWriter(directory: directory)
    #expect(try writer.write(.init()).conflicts == ["roarkt.custom.yaml"])
    #expect(try Data(contentsOf: target) == data)
    try FileManager.default.removeItem(at: link)
    let unowned = Data(("# mine\n" + RimeSettingsPatch.marker + "\npatch: {}\n").utf8)
    try unowned.write(to: link)
    #expect(try writer.write(.init()).conflicts == ["roarkt.custom.yaml"])
    #expect(try Data(contentsOf: link) == unowned)
}

@Test func inputAIFeatureProjectionDefaultsPerKeyAndIgnoresOtherFeatures() throws {
    var settings = AppSettings()
    var ai = InputAISettings()
    ai.enabled = true
    ai.timeout = 17
    settings.input.inputAI = ai
    settings.input.scheme = .flypy
    settings.input.candidateTranslation = false
    let base = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
    let cases: [(String?, Bool)] = [
        (nil, true), ("null", true), ("{}", true),
        (#"{"voice":false}"#, true),
        (#"{"inputMethodAI":null}"#, true),
        (#"{"inputMethodAI":true}"#, true),
        (#"{"inputMethodAI":false}"#, false),
        (#"{"inputMethodAI":false,"voice":"unrelated","futureFlag":{}}"#, false)
    ]
    for (features, enabled) in cases {
        var object = base
        object.removeValue(forKey: "features")
        if let features {
            object["features"] = try JSONSerialization.jsonObject(with: Data(features.utf8), options: .fragmentsAllowed)
        }
        let preferences = InputMethodPreferences.decode(try JSONSerialization.data(withJSONObject: object))
        #expect(preferences.inputMethodAIEnabled == enabled)
        #expect(preferences.allowsInputAI == enabled)
        #expect(preferences.input == settings.input, "Feature flags must not reset candidate or AI configuration")
        #expect(preferences.translation == settings.translation)
        #expect(preferences != InputMethodPreferences(input: settings.input, translation: settings.translation,
                                                     inputMethodAIEnabled: !enabled), "Flag changes must invalidate the read-only settings snapshot")
    }
}

@Test func inputAIFeatureDoesNotEnablePreviouslyDisabledInputAI() throws {
    var settings = AppSettings()
    settings.enabledFeatures.inputMethodAI = true
    #expect(!InputMethodPreferences.decode(try JSONEncoder().encode(settings)).allowsInputAI)
    settings.input.inputAI = InputAISettings()
    #expect(!InputMethodPreferences.decode(try JSONEncoder().encode(settings)).allowsInputAI)
    settings.input.inputAI?.enabled = true
    #expect(InputMethodPreferences.decode(try JSONEncoder().encode(settings)).allowsInputAI)
    settings.enabledFeatures.inputMethodAI = false
    #expect(!InputMethodPreferences.decode(try JSONEncoder().encode(settings)).allowsInputAI)
}
