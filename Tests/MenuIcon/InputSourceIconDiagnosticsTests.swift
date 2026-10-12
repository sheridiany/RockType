import AppKit
import XCTest
import RoarkTCore

@MainActor final class InputSourceIconDiagnosticsTests: XCTestCase {
    func testReadOnlyBundleProbeRejectsMissingEmptyAndEscapingResources() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RockType-icon-probe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("probe")
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["swiftc", "-swift-version", "6", "-parse-as-library"] +
            ["Core/Identifiers.swift", "Installer/tools/InputSourceIconDiagnostics.swift", "Installer/tools/RegisterInputSource.swift"]
                .map { root.appendingPathComponent($0).path } + ["-o", executable.path]
        try compiler.run(); compiler.waitUntilExit()
        XCTAssertEqual(compiler.terminationStatus, 0)
        guard compiler.terminationStatus == 0 else { return }

        let bundle = directory.appendingPathComponent("Synthetic Input.app")
        let resources = bundle.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let icon = resources.appendingPathComponent("SyntheticTemplate.pdf")
        let infoURL = bundle.appendingPathComponent("Contents/Info.plist")
        let keys = ["tsInputModeMenuIconFileKey", "tsInputModeAlternateMenuIconFileKey", "tsInputModePaletteIconFileKey"]
        let modes = Dictionary(uniqueKeysWithValues: [Identifiers.pinyinInputSourceID, Identifiers.flypyInputSourceID].map {
            ($0, Dictionary(uniqueKeysWithValues: keys.map { ($0, icon.lastPathComponent) }))
        })
        var info: [String: Any] = ["CFBundleIdentifier": Identifiers.inputMethodBundleID,
                                  "ComponentInputModeDict": ["tsInputModeListKey": modes]]
        func saveInfo() throws {
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL)
        }
        func drawIcon(filled: Bool) throws {
            var box = CGRect(x: 0, y: 0, width: 22, height: 16)
            let context = try XCTUnwrap(CGContext(icon as CFURL, mediaBox: &box, nil))
            context.beginPDFPage(nil)
            if filled { context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fill(box.insetBy(dx: 2, dy: 2)) }
            context.endPDFPage(); context.closePDF()
        }
        func check(expected: Int32) throws {
            let before = try Data(contentsOf: infoURL)
            let beforeIcon = try? Data(contentsOf: icon)
            let process = Process(), pipe = Pipe()
            process.executableURL = executable
            process.arguments = ["check-icons", bundle.path]
            process.standardOutput = pipe
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, expected)
            let report = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
            XCTAssertEqual(report["resourceCheckPassed"] as? Bool, expected == 0)
            XCTAssertEqual(try Data(contentsOf: infoURL), before)
            XCTAssertEqual(try? Data(contentsOf: icon), beforeIcon, "Diagnostic must never repair or overwrite resources")
        }
        try saveInfo()
        try check(expected: 1) // Declared PDF is absent.
        try drawIcon(filled: false)
        try check(expected: 1) // A parseable but transparent PDF is still unusable.
        try drawIcon(filled: true)
        try check(expected: 0)
        var brokenModes = modes
        brokenModes[Identifiers.flypyInputSourceID]?[keys[1]] = "missing.pdf"
        info["ComponentInputModeDict"] = ["tsInputModeListKey": brokenModes]
        try saveInfo(); try check(expected: 1) // Check every mode and alternate resource.
        brokenModes = modes
        brokenModes[Identifiers.pinyinInputSourceID]?[keys[0]] = "../outside.pdf"
        info["ComponentInputModeDict"] = ["tsInputModeListKey": brokenModes]
        try saveInfo(); try check(expected: 1)
        info["CFBundleIdentifier"] = Identifiers.appBundleID
        try saveInfo(); try check(expected: 1)
    }
}
