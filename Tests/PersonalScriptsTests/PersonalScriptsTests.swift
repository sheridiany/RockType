import Foundation
import Testing

@Test func personalScriptsInTemporaryDirectories() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments = ["python3", "-B", root.appendingPathComponent("Tests/PersonalScriptsTests/checks.py").path]
    task.currentDirectoryURL = root
    let status: Int32 = try await withCheckedThrowingContinuation { continuation in
        task.terminationHandler = { process in
            continuation.resume(returning: process.terminationStatus)
        }
        do { try task.run() }
        catch { continuation.resume(throwing: error) }
    }
    #expect(status == 0)
}
