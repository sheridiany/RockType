import AppKit
import QuartzCore
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["ROARKT_T7_TOOLBAR_BENCHMARK"] == "1"))
func t7CaptureServiceToToolbarLatency() async throws {
    _ = NSApplication.shared
    let capture = SelectionCapture(allowed: { true }, context: {
        .init(source: .init(pid: 0, applicationName: "Synthetic"), isCurrent: { true })
    }, read: { .init(status: .success, text: "Synthetic selection", rect: nil) }, copy: {
        Issue.record("No copy needed for this fixture"); return nil
    })
    let toolbar = SelectionToolbarWindow()
    defer { toolbar.hide() }
    let started = ContinuousClock.now
    let selection = try await capture.capture()
    toolbar.show(snapshot: selection.snapshot, settings: .defaults, perform: { _ in })
    #expect(toolbar.isVisible)
    let panel = try #require(NSApp.windows.first { toolbar.contains($0) })
    panel.displayIfNeeded(); CATransaction.flush()
    let elapsed = started.duration(to: .now).components
    let ms = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
    print(String(format: "t7_synthetic capture_to_toolbar_ordered %.3f ms (excludes AX, mouse debounce and animation)", ms))
}
