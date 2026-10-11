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
    #expect(calls.contains("asuser 501 /usr/bin/sudo -H -u fixture-user -- /Applications/RockType.app/Contents/Helpers/RoarkTRegisterInputSource register /Library/Input Methods/RockType Input.app"))
    #expect(calls.contains("bootout gui/501/com.roarkist.roarkt.translation"))
    #expect(calls.contains("bootstrap gui/501 /Library/LaunchAgents/com.roarkist.roarkt.translation.plist"))
    #expect(calls.contains("open -g /Applications/RockType.app"))
    #expect(!calls.contains(" select "))
    #expect(!calls.contains("HIToolbox"))
    #expect(!calls.contains("RoarkTRegisterInputSource enable"))
    // Offline volume rejection happens before all session operations.
    try "".write(to: log, atomically: true, encoding: .utf8)
    let rejected = try runDistributionCommand("/bin/bash", [fixture.appendingPathComponent("postinstall").path, "package", "/", "/Volumes/Other"])
    #expect(rejected.0 != 0)
    #expect(try String(contentsOf: log, encoding: .utf8).isEmpty)
}

@Test func notarizationRequiresProfileAndAcceptedSubmission() throws {
    let fm = FileManager.default
    let fixture = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: fixture, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: fixture) }
    let log = fixture.appendingPathComponent("calls")
    let mock = fixture.appendingPathComponent("mock")
    try """
    #!/bin/bash
    echo "$*" >> '\(log.path)'
    case "$1" in
      pkgutil) echo 'Developer ID Installer: XIAO BIN (DF7J2VBQD8)';;
      xcrun) if [[ "$2" == notarytool ]]; then echo "{\\"status\\":\\"${FIXTURE_STATUS}\\"}"; fi;;
    esac
    """.write(to: mock, atomically: true, encoding: .utf8)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mock.path)
    var script = try String(contentsOf: distributionRoot.appendingPathComponent("scripts/notarize.sh"), encoding: .utf8)
    script = script.replacingOccurrences(of: "version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \"$repo_dir/App/Info.plist\")", with: "version=0.1.0")
    for command in ["xcrun", "pkgutil", "spctl"] {
        script = script.replacingOccurrences(of: command + " ", with: "'\(mock.path)' " + command + " ")
    }
    let executable = fixture.appendingPathComponent("notarize.sh")
    try script.write(to: executable, atomically: true, encoding: .utf8)
    let pkg = fixture.appendingPathComponent("fixture.pkg")
    try Data().write(to: pkg)
    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "ROARKT_NOTARY_PROFILE")
    let missing = try runDistributionCommand("/bin/zsh", [executable.path, pkg.path], environment: environment)
    #expect(missing.0 != 0)
    #expect(missing.1.contains("ROARKT_NOTARY_PROFILE"))
    #expect(!fm.fileExists(atPath: log.path))
    environment["ROARKT_NOTARY_PROFILE"] = "fixture-profile"
    for status in ["Invalid", "Accepted"] {
        environment["FIXTURE_STATUS"] = status
        try "".write(to: log, atomically: true, encoding: .utf8)
        let result = try runDistributionCommand("/bin/zsh", [executable.path, pkg.path], environment: environment)
        let calls = try String(contentsOf: log, encoding: .utf8)
        #expect((result.0 == 0) == (status == "Accepted"), "\(result.1)")
        #expect(calls.contains("stapler staple") == (status == "Accepted"))
        #expect(calls.contains("stapler validate") == (status == "Accepted"))
    }
}
