import Foundation
import XCTest

final class PackagingChecks: XCTestCase {
    func testIncrementalPackagingReplacesReadOnlyLicenseCopies() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("roarkt-packaging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        func package() throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [root.appendingPathComponent("InputMethod/scripts/package-rime.sh").path]
            var environment = ProcessInfo.processInfo.environment
            environment["TARGET_BUILD_DIR"] = temporary.path
            environment["CONTENTS_FOLDER_PATH"] = "Synthetic Input.app/Contents"
            environment["SRCROOT"] = root.appendingPathComponent("InputMethod").path
            process.environment = environment
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "Incremental factory packaging must replace read-only generated copies")
        }
        try package()
        let licenses = temporary.appendingPathComponent("Synthetic Input.app/Contents/Resources/Licenses")
        let stale = licenses.appendingPathComponent("stale-license.txt")
        try Data("synthetic".utf8).write(to: stale)
        let notice = licenses.appendingPathComponent("THIRD_PARTY_NOTICES.md")
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: notice.path)
        try package()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path), "Removed dependencies must not leave stale notices")
        XCTAssertEqual(try Data(contentsOf: notice), try Data(contentsOf: root.appendingPathComponent("THIRD_PARTY_NOTICES.md")))
    }
}
