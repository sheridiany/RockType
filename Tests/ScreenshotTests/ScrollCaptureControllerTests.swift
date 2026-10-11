import AppKit
import XCTest
import RoarkTCore
@testable import RoarkTApp

@MainActor private final class GatedScrollSource: ScrollFrameSource {
    var stopped = false
    var calls = 0
    var waiting: CheckedContinuation<CGImage, any Error>?
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
    func next() async throws -> CGImage {
        calls += 1
        if calls == 1 { return image }
        return try await withCheckedThrowingContinuation { waiting = $0 }
    }
    func stop() { stopped = true }
    func release() { waiting?.resume(returning: image); waiting = nil }
}
final class ScrollCaptureControllerTests: XCTestCase, @unchecked Sendable {
    private func image() throws -> CGImage {
        let c = try XCTUnwrap(CGContext(data: nil, width: 120, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        c.setFillColor(CGColor(gray: 0.5, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 120, height: 160))
        return try XCTUnwrap(c.makeImage())
    }
    @MainActor private func waitFor(_ predicate: () -> Bool) async {
        for _ in 0..<200 { if predicate() { return }; try? await Task.sleep(for: .milliseconds(5)) }
        XCTFail("Synthetic lifecycle did not reach expected state")
    }
    @MainActor func testFinishDoesNotWaitForInFlightCaptureAndDropsItsLateImage() async throws {
        let source = GatedScrollSource(try image()), engine = ScrollStitcher()
        let controller = ScrollCaptureController(allowed: { true }, prepare: { source }, stitcher: engine, interval: .milliseconds(1))
        var output: CGImage?
        controller.onComplete = { output = $0 }
        controller.start(); await waitFor { source.waiting != nil }
        XCTAssertNotNil(controller.thumbnail); XCTAssertTrue(controller.canFinish)
        controller.finish(); await waitFor { output != nil }
        XCTAssertTrue(source.stopped); XCTAssertEqual(output?.height, 160)
        XCTAssertEqual(controller.phase, .closed); XCTAssertNil(controller.thumbnail)
        source.release(); try await Task.sleep(for: .milliseconds(20))
        do { _ = try await engine.finish(); XCTFail("Finalization must release engine strips") } catch ScrollStitcher.Failure.empty { }
    }
    @MainActor func testCancelClearsPreviewAndEngineBeforeLateCaptureReturns() async throws {
        let source = GatedScrollSource(try image()), engine = ScrollStitcher()
        let controller = ScrollCaptureController(allowed: { true }, prepare: { source }, stitcher: engine, interval: .milliseconds(1))
        var cancelled = 0, completed = 0
        controller.onCancel = { cancelled += 1 }; controller.onComplete = { _ in completed += 1 }
        controller.start(); await waitFor { source.waiting != nil }
        controller.cancel(); controller.cancel()
        XCTAssertTrue(source.stopped); XCTAssertNil(controller.thumbnail); XCTAssertEqual(controller.height, 0); XCTAssertEqual(cancelled, 1)
        source.release(); try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(completed, 0)
        do { _ = try await engine.finish(); XCTFail("Cancel must release all strips") } catch ScrollStitcher.Failure.empty { }
    }
    @MainActor func testRevokedProtectionCancelsWhileCaptureIsPending() async throws {
        let source = GatedScrollSource(try image())
        var allowed = true, failed = false
        let controller = ScrollCaptureController(allowed: { allowed }, prepare: { source }, interval: .milliseconds(1))
        controller.onFailure = { _ in failed = true }
        controller.start(); await waitFor { source.waiting != nil }
        allowed = false; await waitFor { failed }
        XCTAssertEqual(controller.phase, .closed); XCTAssertNil(controller.thumbnail); XCTAssertTrue(source.stopped)
        source.release()
    }
    @MainActor func testCancelledPreparationStopsLateSourceAndNeverSamples() async throws {
        let source = GatedScrollSource(try image())
        var ready: CheckedContinuation<any ScrollFrameSource, any Error>?
        let controller = ScrollCaptureController(allowed: { true }, prepare: { try await withCheckedThrowingContinuation { ready = $0 } })
        controller.start(); await waitFor { ready != nil }
        controller.cancel(); ready?.resume(returning: source)
        await waitFor { source.stopped }; XCTAssertEqual(source.calls, 0)
    }
    @MainActor func testCompletedScrollEntersExistingPreviewSession() async throws {
        let source = GatedScrollSource(try image())
        var panels = 0
        let coordinator = ScreenshotCoordinator(allowed: { true }, presentPreview: { _ in panels += 1 })
        coordinator.start(); defer { source.release(); coordinator.stop() }
        let controller = ScrollCaptureController(allowed: { true }, prepare: { source }, interval: .milliseconds(1))
        controller.onComplete = { coordinator.openImage($0, origin: "滚动长截图") }
        controller.start(); await waitFor { controller.canFinish }
        controller.finish(); await waitFor { coordinator.session != nil }
        XCTAssertEqual(panels, 1); XCTAssertEqual(coordinator.session?.origin, "滚动长截图")
        XCTAssertEqual(coordinator.session?.image?.height, 160)
        coordinator.closePreview(); XCTAssertNil(coordinator.session)
    }
    @MainActor func testEntryRequiresSelectionAndPinUsesProtectedNormalSession() throws {
        let canvas = CaptureCanvas(frame: CGRect(x: 0, y: 0, width: 120, height: 160), image: try image())
        canvas.allowed = { true }
        var starts = 0; canvas.onScrollCapture = { starts += 1 }
        let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "l", charactersIgnoringModifiers: "l", isARepeat: false, keyCode: 37))
        canvas.keyDown(with: key); XCTAssertEqual(starts, 0)
        canvas.restore(CGRect(x: 10, y: 10, width: 80, height: 80))
        canvas.keyDown(with: key); XCTAssertEqual(starts, 1)
        var allowed = true, pins = 0
        let session = ScreenshotSession(image: try image(), origin: "Synthetic scroll", settings: { .defaults }, verified: { _, _ in false }, allowed: { allowed })
        session.onPin = { _ in pins += 1; return true }
        allowed = false; session.pinImage(); XCTAssertEqual(pins, 0)
        allowed = true; session.pinImage(); XCTAssertEqual(pins, 1); XCTAssertNil(session.image)
        session.pinImage(); XCTAssertEqual(pins, 1)
    }
}
