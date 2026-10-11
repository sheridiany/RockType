import Foundation
import XCTest

// Keep GPL production sources in isolated executables, never in an MIT app target.
final class InputMethodChecks: XCTestCase {
    func testProductionInputMethod() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent("scripts/test-ime.sh").path]
        var environment = ProcessInfo.processInfo.environment
        environment["ROARKT_IME_FROM_SWIFTPM"] = "1"
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "Production session/modifier/panel checks failed")
    }
}

final class InputMethodPathChecks: XCTestCase {
    /// `URL.path()` percent-encodes spaces, so "Application Support" became a second
    /// "Application%20Support" Rime directory that silently ignored the user's data.
    func testFileSystemPathsAreNotPercentEncoded() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("InputMethod/sources")
        for name in try FileManager.default.contentsOfDirectory(atPath: sources.path) where name.hasSuffix(".swift") {
            let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            XCTAssertFalse(text.contains(".path()"), "\(name) uses percent-encoded URL.path(); use path(percentEncoded: false)")
        }
    }
}
