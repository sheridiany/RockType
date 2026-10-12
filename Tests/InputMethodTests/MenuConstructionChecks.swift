import Foundation
import XCTest

final class MenuConstructionChecks: XCTestCase {
    func testAtomicInputMethodReplacementNeverRemovesInstalledPath() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RockType-replacement-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("replacement-check")
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["swiftc", "-swift-version", "6", "-parse-as-library",
            root.appendingPathComponent("Core/Identifiers.swift").path,
            root.appendingPathComponent("Installer/tools/AtomicInputMethodReplacement.swift").path,
            root.appendingPathComponent("Tests/InputMethodTests/AtomicReplacementProbe.swift").path,
            "-o", executable.path]
        try compiler.run(); compiler.waitUntilExit()
        XCTAssertEqual(compiler.terminationStatus, 0)
        guard compiler.terminationStatus == 0 else { return }
        let process = Process()
        process.executableURL = executable
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .exit)
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testProductionMenuConstructionAndActionDispatchWithoutInputMethod() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RockType-menu-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("menu-check")
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["swiftc", "-swift-version", "6", "-parse-as-library",
            root.appendingPathComponent("InputMethod/sources/RoarkTInputMenu.swift").path,
            root.appendingPathComponent("Tests/InputMethodTests/MenuConstructionProbe.swift").path,
            "-o", executable.path]
        try compiler.run()
        compiler.waitUntilExit()
        XCTAssertEqual(compiler.terminationStatus, 0)
        guard compiler.terminationStatus == 0 else { return }
        let process = Process()
        process.executableURL = executable
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .exit)
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
