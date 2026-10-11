import Foundation
import XCTest

final class InputMethodLocalizationTests: XCTestCase {
    /// Compile the shipped catalogs, then resolve their unchanged lookup keys using
    /// Bundle. This catches missing English values and input-source names that a
    /// source-only text check cannot catch. No IMK process or notifications run.
    func testCompiledMenuNotificationAndInputSourceNames() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("RockType-localization-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }
        for name in ["Localizable", "InfoPlist"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["xcstringstool", "compile", root.appendingPathComponent("InputMethod/resources/\(name).xcstrings").path,
                                 "--output-directory", output.path]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
        }
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let bundle = try XCTUnwrap(Bundle(path: output.appendingPathComponent(language + ".lproj").path))
            func value(_ key: String, table: String = "Localizable") -> String {
                bundle.localizedString(forKey: key, value: nil, table: table)
            }
            XCTAssertEqual(value("Squirrel"), "RockType", "notification title in \(language)")
            XCTAssertEqual(value("com.roarkist.inputmethod.RoarkT.pinyin", table: "InfoPlist"), "RockType Pinyin")
            XCTAssertEqual(value("com.roarkist.inputmethod.RoarkT.flypy", table: "InfoPlist"), "RockType Shuangpin")
            for key in ["Logs...", "Settings...", "Check for updates...", "Rime Wiki..."] {
                XCTAssertNotEqual(value(key), key, "lookup key must resolve in \(language)")
                XCTAssertTrue(value(key).hasSuffix("…"))
                XCTAssertFalse(value(key).contains("..."))
            }
            for key in ["deploy_start", "deploy_success", "deploy_failure"] {
                XCTAssertNotEqual(value(key), key)
                XCTAssertFalse(value(key).contains("Squirrel"))
            }
            XCTAssertTrue(value("Settings...").contains(language == "en" ? "Folder" : language == "zh-Hans" ? "文件夹" : "資料夾"))
        }
    }
}
