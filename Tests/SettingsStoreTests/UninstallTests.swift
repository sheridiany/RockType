import Foundation
import Testing
import RoarkTCore
@testable import RoarkTApp

@Test func uninstallRemovesPrivateProfileAndPreservesOtherInputMethod() throws {
    let fm = FileManager.default
    let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: home) }
    let appData = home.appendingPathComponent("Library/Application Support/" + Identifiers.applicationSupportFolder)
    try fm.createDirectory(at: appData.appendingPathComponent("VoiceModels"), withIntermediateDirectories: true)
    // Only the explicitly owned screenshot archive is removable inside this folder.
    let displayNamed = home.appendingPathComponent("Library/Application Support/RockType")
    try fm.createDirectory(at: displayNamed, withIntermediateDirectories: true)
    let screenshots = Identifiers.screenshotHistoryDirectory(home: home)
    try fm.createDirectory(at: screenshots, withIntermediateDirectories: true)
    try Data("synthetic archive".utf8).write(to: screenshots.appendingPathComponent("index.json"))
    let unrelated = displayNamed.appendingPathComponent("unrelated.txt")
    try Data("preserve".utf8).write(to: unrelated)
    let privateRime = Identifiers.rimeUserDirectory(home: home)
    let otherRime = home.appendingPathComponent("Library/Rime")
    for directory in [privateRime, otherRime] {
        try fm.createDirectory(at: directory.appendingPathComponent("build"), withIntermediateDirectories: true)
        for name in ["roarkt_zh.userdb", "roarkt_en.userdb", "user.yaml", "installation.yaml", "default.custom.yaml", "build/roarkt.prism.bin"] {
            try Data("fixture".utf8).write(to: directory.appendingPathComponent(name))
        }
    }
    try UninstallData.remove(in: home)
    #expect(!fm.fileExists(atPath: screenshots.path))
    #expect(try Data(contentsOf: unrelated) == Data("preserve".utf8))
    #expect(!fm.fileExists(atPath: appData.path))
    #expect(!fm.fileExists(atPath: privateRime.path))
    #expect(fm.fileExists(atPath: displayNamed.path), "The display name must not change internal data ownership")
    for name in ["roarkt_zh.userdb", "roarkt_en.userdb", "user.yaml", "installation.yaml", "default.custom.yaml", "build/roarkt.prism.bin"] {
        #expect(try Data(contentsOf: otherRime.appendingPathComponent(name)) == Data("fixture".utf8))
    }
    try UninstallData.remove(in: home)
}

@Test func uninstallRefusesRedirectedSupportAndPrivateRimeParent() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: root) }
    let target = root.appendingPathComponent("other")
    try fm.createDirectory(at: target.appendingPathComponent("Rime"), withIntermediateDirectories: true)
    let file = target.appendingPathComponent("Rime/roarkt.schema.yaml")
    try Data("keep".utf8).write(to: file)
    for name in ["Library/Application Support", "Library/Application Support/" + Identifiers.applicationSupportFolder, "Library/Application Support/RockType", "Library/Application Support/RockType/ScreenshotHistory"] {
        let home = root.appendingPathComponent(UUID().uuidString)
        let link = home.appendingPathComponent(name)
        try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: (any Error).self) { try UninstallData.remove(in: home) }
        #expect(try Data(contentsOf: file) == Data("keep".utf8))
    }
}

@MainActor @Test func uninstallAppleScriptQuotesFixedCommandSafely() {
    #expect(UninstallController.appleScriptLiteral("a\\b\"c") == "\"a\\\\b\\\"c\"")
}
