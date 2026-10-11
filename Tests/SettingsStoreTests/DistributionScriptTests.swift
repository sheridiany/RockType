import Foundation
import Testing

private let distributionRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func runDistributionCommand(_ executable: String, _ arguments: [String], environment: [String: String]? = nil) throws -> (Int32, String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let environment { process.environment = environment }
    let output = Pipe()
    process.standardOutput = output; process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

@Test func installerOnlyRegistersSourcesInUserSessions() throws {
    let fm = FileManager.default
    let fixture = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: fixture, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: fixture) }
    let log = fixture.appendingPathComponent("calls")
    let mock = fixture.appendingPathComponent("mock")
    // Replace system command paths only in fixture copies; production has no test bypass.
    try """
    #!/bin/bash
    printf '%s\\n' "$*" >> '\(log.path)'
    case "$1" in
      ps) echo '501 /System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow';;
      id) echo fixture-user;;
      stat) echo 501;;
    esac
    """.write(to: mock, atomically: true, encoding: .utf8)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mock.path)
    for name in ["session-common.sh", "preinstall", "postinstall"] {
        var script = try String(contentsOf: distributionRoot.appendingPathComponent("Installer/scripts/" + name), encoding: .utf8)
        for (path, command) in [("/bin/ps", "ps"), ("/usr/bin/id", "id"), ("/usr/bin/stat", "stat"), ("/bin/launchctl", "launchctl")] {
            script = script.replacingOccurrences(of: path, with: "'\(mock.path)' \(command)")
        }
        try script.write(to: fixture.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    for name in ["preinstall", "postinstall"] {
        let result = try runDistributionCommand("/bin/bash", [fixture.appendingPathComponent(name).path, "package", "/", "/"])
        #expect(result.0 == 0, "\(result.1)")
    }
    let calls = try String(contentsOf: log, encoding: .utf8)
    #expect(calls.contains("asuser 501 /usr/bin/sudo -H -u fixture-user -- /Applications/RoarkT.app/Contents/Helpers/RoarkTRegisterInputSource register /Library/Input Methods/RoarkT Input.app"))
    #expect(calls.contains("bootout gui/501/com.roarkist.roarkt.translation"))
    #expect(calls.contains("bootstrap gui/501 /Library/LaunchAgents/com.roarkist.roarkt.translation.plist"))
    #expect(calls.contains("open -g /Applications/RoarkT.app"))
    #expect(!calls.contains(" select "))
    #expect(!calls.contains("HIToolbox"))
    #expect(!calls.contains("RoarkTRegisterInputSource enable"))
    // Offline volume rejection happens before all session operations.
    try "".write(to: log, atomically: true, encoding: .utf8)
    let rejected = try runDistributionCommand("/bin/bash", [fixture.appendingPathComponent("postinstall").path, "package", "/", "/Volumes/Other"])
    #expect(rejected.0 != 0)
    #expect(try String(contentsOf: log, encoding: .utf8).isEmpty)
}
