import Foundation
import Testing
import RoarkTCore

@Test func personalScriptsInTemporaryDirectories() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("rocktype-settings-fixture-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: fixture) }
    let initial = fixture.appendingPathComponent("initial")
    let updated = fixture.appendingPathComponent("updated")
    let writer = RimeSettingsPatchWriter(directory: updated)
    #expect(try writer.write(InputSettings()).conflicts.isEmpty)
    try FileManager.default.copyItem(at: updated, to: initial)
    let personal = updated.appendingPathComponent("roarkt_personal.patch.yaml")
    let sentinel = Data("# personal ownership sentinel\n".utf8)
    try sentinel.write(to: personal)
    var settings = InputSettings()
    settings.englishCompletion = false
    settings.shiftTogglesLanguage = false
    let result = try writer.write(settings)
    #expect(result.changed && result.conflicts.isEmpty)
    #expect(try Data(contentsOf: personal) == sentinel)
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments = ["python3", "-B", root.appendingPathComponent("Tests/PersonalScriptsTests/checks.py").path]
    task.currentDirectoryURL = root
    task.environment = ProcessInfo.processInfo.environment.merging(["ROARKT_SETTINGS_FIXTURE": fixture.path]) { _, new in new }
    let status: Int32 = try await withCheckedThrowingContinuation { continuation in
        task.terminationHandler = { process in
            continuation.resume(returning: process.terminationStatus)
        }
        do { try task.run() }
        catch { continuation.resume(throwing: error) }
    }
    #expect(status == 0)
}
