import Foundation
import Testing
import RoarkTCore
@testable import RoarkTApp

@Test func toolPreferenceEditsRetainUnrelatedPreferencesAndRuntimeDefaults() throws {
    let unknown = ScreenshotAnnotationStyle(colorHex: "ABCDEF", width: 9)
    let original = ["future-tool": unknown, "text": ScreenshotAnnotationStyle(colorHex: "FFFFFF", width: 22)]
    let result = ScreenshotStylePreferences.updating(.arrow, in: original) { $0.colorHex = "123456" }
    #expect(result["future-tool"] == unknown)
    #expect(result["text"] == original["text"])
    #expect(result["arrow"]?.width == ScreenshotTool.arrow.defaultWidth)
    let limited = ScreenshotStylePreferences.updating(.text, in: result) { $0.width = 1000 }
    #expect(limited["text"]?.width == ScreenshotTool.text.widthRange.upperBound)
    var settings = ScreenshotSettings()
    settings.annotationStyles = limited
    let decoded = try JSONDecoder().decode(ScreenshotSettings.self, from: JSONEncoder().encode(settings))
    #expect(ScreenshotTool.arrow.style(from: decoded.annotationStyles ?? [:]).colorHex == "123456")
    #expect(decoded.annotationStyles?["future-tool"] == unknown)
}

@Test func aboutDocumentsResolveOnlyPackagedResources() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Licenses"), withIntermediateDirectories: true)
    #expect(AboutDocuments.thirdParty.url(resources: root) == nil)
    let path = root.appendingPathComponent("Licenses/THIRD_PARTY_NOTICES.md")
    try Data("Synthetic notice".utf8).write(to: path)
    #expect(AboutDocuments.thirdParty.url(resources: root) == path)
    #expect(AboutDocuments.appLicense.url(resources: root) == nil)
    #expect(AboutDocuments.version(["CFBundleShortVersionString": "2.0", "CFBundleVersion": "42"]) == "2.0（构建 42）")
}

@Test func historyPreferenceDefaultsForExistingSettingsAndPersistsZero() throws {
    let old = Data(#"{"format":"png","ocrLanguages":["en-US"]}"#.utf8)
    var settings = try JSONDecoder().decode(ScreenshotSettings.self, from: old)
    #expect(settings.pinHistoryLimit == nil)
    settings.pinHistoryLimit = 0
    let decoded = try JSONDecoder().decode(ScreenshotSettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded.pinHistoryLimit == 0)
}
