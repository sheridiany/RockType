import Foundation
import XCTest

final class MenuIconTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    @discardableResult
    private func run(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    func testTemplateAndSystemRenderer() throws {
        let output = root.appendingPathComponent(".build/ime-evidence")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let pdf = output.appendingPathComponent("roarktMenuTemplate.pdf")
        XCTAssertEqual(try run(["swift", root.appendingPathComponent("scripts/generate-menu-icon.swift").path, pdf.path]), 0)
        XCTAssertEqual(try run(["swift", root.appendingPathComponent("Tests/MenuIcon/test-menu-icon.swift").path, pdf.path]), 0)
        let probe = output.appendingPathComponent("system-renderer-probe")
        XCTAssertEqual(try run(["--sdk", "macosx", "clang", "-fobjc-arc", "-framework", "AppKit", root.appendingPathComponent("Tests/MenuIcon/SystemRendererProbe.m").path, "-o", probe.path]), 0)
        defer { try? FileManager.default.removeItem(at: probe) }
        let process = Process()
        process.executableURL = probe
        process.arguments = [pdf.path, output.appendingPathComponent("menu-icon-system.png").path]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 77 { throw XCTSkip("System diagnostic renderer unavailable; installed-menu geometry needs manual verification") }
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testBothInputSourcesReferenceTemplate() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("InputMethod/resources/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let component = try XCTUnwrap(plist["ComponentInputModeDict"] as? [String: Any])
        let modes = try XCTUnwrap(component["tsInputModeListKey"] as? [String: [String: Any]])
        XCTAssertEqual(modes.count, 2)
        for mode in modes.values {
            for key in ["tsInputModeMenuIconFileKey", "tsInputModeAlternateMenuIconFileKey", "tsInputModePaletteIconFileKey"] {
                XCTAssertEqual(mode[key] as? String, "roarktMenuTemplate.pdf")
            }
        }
    }
}
