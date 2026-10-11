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
