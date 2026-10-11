import Foundation
import Testing
import RoarkTCore
@testable import RoarkTApp

@Test func uninstallRemovesOnlyOwnedDataAndPreservesSharedRime() throws {
    let fm = FileManager.default
    let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: home) }
    for path in ["Library/Application Support/RoarkT/VoiceModels", "Library/Rime/build", "Library/Rime/roarkt_zh.userdb"] {
        try fm.createDirectory(at: home.appendingPathComponent(path), withIntermediateDirectories: true)
    }
    let removed = ["roarkt.schema.yaml", "roarkt_flypy.custom.yaml", "roarkt_en.dict.yaml", "build/roarkt.prism.bin"]
    let preserved = ["roarkt.custom.yaml", "default.custom.yaml", "squirrel.custom.yaml", "luna_pinyin.userdb", "user.yaml", "installation.yaml", "roarkt_other.schema.yaml"]
    for name in removed + preserved {
        let content = name == "roarkt_flypy.custom.yaml" ? RimeSettingsPatch.marker + "\npatch: {}\n" : "fixture"
        try Data(content.utf8).write(to: home.appendingPathComponent("Library/Rime/" + name))
    }
    try UninstallData.remove(in: home)
    #expect(!fm.fileExists(atPath: home.appendingPathComponent("Library/Application Support/RoarkT").path))
    for name in removed + ["roarkt_zh.userdb"] {
        #expect(!fm.fileExists(atPath: home.appendingPathComponent("Library/Rime/" + name).path))
    }
    for name in preserved {
        #expect(try Data(contentsOf: home.appendingPathComponent("Library/Rime/" + name)) == Data("fixture".utf8))
    }
    try UninstallData.remove(in: home) // Already removed data is safe to retry.
}

@Test func uninstallRefusesRedirectedRimeAndSupport() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: root) }
    let target = root.appendingPathComponent("other")
    try fm.createDirectory(at: target, withIntermediateDirectories: true)
    let file = target.appendingPathComponent("roarkt.schema.yaml")
    try Data("keep".utf8).write(to: file)
    for name in ["Rime", "Application Support"] {
        let home = root.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: home.appendingPathComponent("Library"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: home.appendingPathComponent("Library/" + name), withDestinationURL: target)
        #expect(throws: (any Error).self) { try UninstallData.remove(in: home) }
        #expect(try Data(contentsOf: file) == Data("keep".utf8))
    }
}

@MainActor @Test func uninstallAppleScriptQuotesFixedCommandSafely() {
    #expect(UninstallController.appleScriptLiteral("a\\b\"c") == "\"a\\\\b\\\"c\"")
}
