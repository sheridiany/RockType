import Foundation
import Testing
@testable import RoarkTCore

@Test func diagnosticsCannotPersistErrorDescriptionsHeadersURLsOrBodies() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let log = try DiagnosticLog(directory: root)
    // Synthetic canaries, never actual user data or credentials.
    let rawError = NSError(domain: "https://example.invalid/?query=QUERY_CANARY", code: 400, userInfo: [
        NSLocalizedDescriptionKey: "Authorization: Bearer AUTH_CANARY body=BODY_CANARY",
        NSURLErrorFailingURLStringErrorKey: "https://example.invalid/?token=QUERY_CANARY",
    ])
    try await log.record(.init(action: .aiRequest, status: .failed, duration: 0.012, failure: .init(error: rawError)))
    let text = try String(contentsOf: root.appendingPathComponent("diagnostics.log"), encoding: .utf8)
    for forbidden in ["QUERY_CANARY", "AUTH_CANARY", "BODY_CANARY", "Authorization", "https://", "body="] {
        #expect(!text.contains(forbidden))
    }
    #expect(text.contains("unknown") && text.contains("aiRequest") && text.contains("12"))
    let attrs = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("diagnostics.log").path)
    #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func diagnosticsRotationEnforcesSizeAndRetention() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let log = try DiagnosticLog(directory: root, maximumBytes: 300, fileCount: 5)
    for _ in 0..<30 { try await log.record(.init(action: .settingsSave, status: .succeeded)) }
    let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    #expect(files.count == 5)
    for file in files {
        let data = try Data(contentsOf: file)
        #expect(data.count <= 300)
        for line in data.split(separator: 10) { #expect(throws: Never.self) { try JSONSerialization.jsonObject(with: Data(line)) } }
    }
}

@Test func diagnosticsZIPContainsOnlyWhitelistedSanitizedRecords() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let logs = root.appendingPathComponent("logs")
    let log = try DiagnosticLog(directory: logs)
    try await log.record(.init(action: .diagnosticExport, status: .started))
    try Data("EXCLUDED_CANARY".utf8).write(to: logs.appendingPathComponent("unrelated.txt"))
    let current = logs.appendingPathComponent("diagnostics.log")
    var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: current)) as? [String: Any])
    json["body"] = "BODY_CANARY"
    try JSONSerialization.data(withJSONObject: json).write(to: current)
    let archive = root.appendingPathComponent("export.zip")
    try await log.exportZIP(to: archive)
    #expect(FileManager.default.fileExists(atPath: archive.path))
    await #expect(throws: DiagnosticLog.Failure.destinationExists) { try await log.exportZIP(to: archive) }
    let unpacked = root.appendingPathComponent("unpacked")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-x", "-k", archive.path, unpacked.path]
    try process.run(); process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    let directory = unpacked.appendingPathComponent("RoarkT-Diagnostics")
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    #expect(files.map(\.lastPathComponent) == ["diagnostics.log"])
    let text = try String(contentsOf: files[0], encoding: .utf8)
    #expect(!text.contains("BODY_CANARY") && !text.contains("EXCLUDED_CANARY"))
}

@Test func diagnosticsRejectInvalidLimitsAndMalformedExport() async throws {
    #expect(throws: DiagnosticLog.Failure.invalidLimits) { try DiagnosticLog(maximumBytes: 3 * 1024 * 1024) }
    #expect(throws: DiagnosticLog.Failure.invalidLimits) { try DiagnosticLog(fileCount: 6) }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let log = try DiagnosticLog(directory: root)
    try Data("unstructured body".utf8).write(to: root.appendingPathComponent("diagnostics.log"))
    await #expect(throws: DiagnosticLog.Failure.exportFailed) { try await log.exportZIP(to: root.appendingPathComponent("export.zip")) }
}
