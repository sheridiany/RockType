import AppKit
import Testing
import RoarkTCore
import RoarkTPlatform
@testable import RoarkTApp

@Suite(.serialized) @MainActor struct G1ScreenshotFeatureTests {
    private func image() throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try #require(context.makeImage())
    }
    @Test func disabledCaptureCancelsPreviewAndLateFramesAndCanRestart() async throws {
        var settings = AppSettings.defaults, captures = 0, reads = 0
        var pending: CheckedContinuation<[ScreenCapture.Frame], Error>?
        let history = ScreenshotHistory(allowed: { true }, recognize: { _, _ in "Synthetic" })
        let coordinator = ScreenshotCoordinator(captureFrames: {
            captures += 1; return try await withCheckedThrowingContinuation { pending = $0 }
        }, allowed: { true }, history: history, readClipboard: { reads += 1; return nil }, presentPreview: { _ in })
        coordinator.readSettings = { settings }; coordinator.start(); defer { coordinator.stop() }
        let image = try image()
        coordinator.openImage(image, origin: "Synthetic")
        let previous = try #require(coordinator.session)
        coordinator.capture()
        for _ in 0..<1000 where pending == nil { await Task.yield() }
        try #require(pending != nil)
        settings.enabledFeatures.screenshot = false; coordinator.settingsChanged()
        #expect(coordinator.session == nil && previous.image == nil && !history.enabled)
        pending?.resume(returning: []); pending = nil
        coordinator.capture(); coordinator.openClipboardImage(); coordinator.openImage(image, origin: "Synthetic")
        for _ in 0..<20 { await Task.yield() }
        #expect(captures == 1 && reads == 0 && coordinator.session == nil)
        settings.enabledFeatures.screenshot = true; coordinator.settingsChanged()
        coordinator.openImage(image, origin: "Synthetic")
        #expect(coordinator.session?.image != nil && history.enabled)
        settings.enabledFeatures.screenshotHistory = false; coordinator.settingsChanged()
        #expect(history.record(image) == nil && history.entries.isEmpty)
        settings.enabledFeatures.screenshotHistory = true; coordinator.settingsChanged()
        #expect(history.record(image) != nil)
    }
    @Test func historyDisableClearsMemoryButPreservesExplicitDiskArchive() async throws {
        let resolved = realpath(FileManager.default.temporaryDirectory.path, nil)
        defer { free(resolved) }
        let directory = URL(fileURLWithPath: String(cString: try #require(resolved))).appendingPathComponent("synthetic-g1-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = ScreenshotHistoryDisk(folder: directory)
        let history = ScreenshotHistory(disk: disk, allowed: { true }, recognize: { _, _ in "Synthetic" })
        var settings = ScreenshotSettings(); settings.historyOnDisk = true
        history.start(settings); defer { history.stop() }
        await history.flush()
        let image = try image()
        try #require(history.record(image) != nil)
        await history.flush(cancelRecognition: true)
        history.setEnabled(false)
        #expect(history.entries.isEmpty && history.record(image) == nil && !history.loading && !history.syncing)
        let stored = try await disk.load(allowed: { true })
        #expect(stored.count == 1)
        history.setEnabled(true)
        await history.flush()
        #expect(history.entries.count == 1)
    }
    @Test func disabledPinningRejectsNewPinsButKeepsExistingClosable() async throws {
        var allowed = true
        let pins = PinnedImageController(allowed: { allowed }, copyImage: { _ in }, showsMenu: false, show: { _ in }, present: { _ in })
        defer { pins.closeAll() }
        let image = try image(), rect = CGRect(x: 0, y: 0, width: 80, height: 80)
        try #require(pins.pin(image, at: rect))
        pins.featureEnabled = false
        #expect(pins.panels.count == 1 && !pins.pin(image, at: rect) && !pins.restoreLast())
        pins.closeGroup(); #expect(pins.panels.isEmpty)
        pins.featureEnabled = true
        #expect(pins.restoreLast() && pins.panels.count == 1)
        var settings = AppSettings.defaults; settings.enabledFeatures.pinning = false
        let session = ScreenshotSession(image: image, origin: "Synthetic", settings: { settings }, verified: { _, _ in false }, allowed: { true })
        var called = false; session.onPin = { _ in called = true; return true }
        session.pinDisplayedImage(); #expect(!called && !session.pinningEnabled)
        settings.enabledFeatures.pinning = true; session.pinDisplayedImage(); #expect(called)
        session.close()
        pins.featureEnabled = false; pins.closeGroup(); pins.setHistoryLimit(10)
        allowed = false
        let deadline = ContinuousClock.now + .seconds(2)
        while !pins.history.entries.isEmpty && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(pins.history.entries.isEmpty, "Protection must still clear retained pin history while the feature is disabled")
    }
}
