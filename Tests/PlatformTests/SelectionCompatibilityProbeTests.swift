import AppKit
import XCTest
@testable import RoarkTPlatform

/// Explicit opt-in diagnostics. Never logs selected text, titles, paths or clipboard contents.
final class SelectionCompatibilityProbeTests: XCTestCase {
    @MainActor func testInstalledApplicationsInventory() throws {
        guard ProcessInfo.processInfo.environment["ROARKT_SELECTION_INVENTORY"] == "1" else { throw XCTSkip("Opt-in installation inventory") }
        for (name, id) in [("TextEdit", "com.apple.TextEdit"), ("Notes", "com.apple.Notes"),
            ("Safari", "com.apple.Safari"), ("Chrome", "com.google.Chrome"),
            ("VSCode", "com.microsoft.VSCode"), ("Xcode", "com.apple.dt.Xcode"),
            ("Terminal", "com.apple.Terminal"), ("iTerm2", "com.googlecode.iterm2"),
            ("Ghostty", "com.mitchellh.ghostty"), ("WeChat", "com.tencent.xinWeChat"),
            ("Feishu", "com.electron.lark"), ("Pages", "com.apple.iWork.Pages"),
            ("Preview", "com.apple.Preview"), ("Notion", "notion.id"), ("Obsidian", "md.obsidian")] {
            let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
                .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            print("selection_inventory \(name) \(installed ? "installed" : "not-found")")
        }
        print("selection_probe_permission \(Accessibility.isTrusted() ? "granted" : "missing")")
    }

    @MainActor func testExplicitSyntheticSelectionProbe() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let expected = environment["ROARKT_SELECTION_PROBE_BUNDLE"], !expected.isEmpty else { throw XCTSkip("Opt-in manual selection probe") }
        // Gives the operator time to focus the already prepared synthetic document. No activation.
        try await Task.sleep(for: .seconds(5))
        guard Accessibility.frontmostApplication?.bundleID == expected else { throw XCTSkip("Expected source is not foreground") }
        guard SecureInput.status() == .allowed else { throw XCTSkip("Protection/permission does not permit reading") }
        let source = SelectionSource()
        let reading = SelectionReader.read()
        if reading.status == .success {
            XCTAssertTrue(reading.text == "RockType compatibility 42", "Select only the documented synthetic sample")
            print("selection_probe direct \(reading.text == "RockType compatibility 42" ? "pass" : "mismatch")")
            return
        }
        guard reading.status == .unsupported, environment["ROARKT_SELECTION_PROBE_COPY"] == "1",
              source?.isCurrent == true else {
            print("selection_probe direct-status \(reading.status); copy-not-run")
            return
        }
        let text = try await Clipboard.shared.copySelectionFallback()
        XCTAssertTrue(source?.isCurrent == true)
        XCTAssertTrue(text == "RockType compatibility 42", "Select only the documented synthetic sample")
        print("selection_probe fallback \(text == "RockType compatibility 42" ? "pass" : "mismatch")")
    }
}
