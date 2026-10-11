import AppKit
import XCTest
import RoarkTPlatform
@testable import RoarkTApp

final class ElementQueryTests: XCTestCase, @unchecked Sendable {
    @MainActor func testMissingPermissionOrProtectionNeverStartsReader() {
        let query = CaptureElementQuery(permitted: { false }, reader: { _ in XCTFail("Protected query must not read AX"); return nil })
        var completed = false
        query.start(at: .zero) { result in XCTAssertNil(result); completed = true }
        XCTAssertTrue(completed)
    }
    @MainActor func testTimeoutFallsBackAndRepeatedRequestDoesNotQueueMoreWorkers() async {
        let entered = expectation(description: "worker entered"), timeout = expectation(description: "deadline"), finished = expectation(description: "worker finished")
        let gate = DispatchSemaphore(value: 0)
        let result = CaptureAccessibility.Snapshot(window: CGRect(x: 0, y: 0, width: 400, height: 300), rectangles: [])
        let query = CaptureElementQuery(timeout: .milliseconds(30), permitted: { true }, reader: { _ in
            XCTAssertFalse(Thread.isMainThread); entered.fulfill()
            _ = gate.wait(timeout: .now() + 2); finished.fulfill(); return result
        })
        var deliveries = 0
        query.start(at: .zero) { value in deliveries += 1; XCTAssertNil(value); timeout.fulfill() }
        await fulfillment(of: [entered, timeout], timeout: 1)
        var fallback = false
        query.start(at: .zero) { value in XCTAssertNil(value); fallback = true }
        XCTAssertTrue(fallback)
        gate.signal(); await fulfillment(of: [finished], timeout: 1)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(deliveries, 1)
    }
    @MainActor func testCancellationDropsLateGeometry() async {
        let entered = expectation(description: "worker entered"), finished = expectation(description: "worker finished")
        let gate = DispatchSemaphore(value: 0)
        let query = CaptureElementQuery(permitted: { true }, reader: { _ in
            entered.fulfill(); _ = gate.wait(timeout: .now() + 2); finished.fulfill()
            return .init(window: CGRect(x: 0, y: 0, width: 100, height: 100), rectangles: [])
        })
        var deliveries = 0
        query.start(at: .zero) { _ in deliveries += 1 }
        await fulfillment(of: [entered], timeout: 1)
        query.cancel(); gate.signal(); await fulfillment(of: [finished], timeout: 1)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(deliveries, 0)
    }
    @MainActor func testProtectionChangedWhileReadingDiscardsGeometry() async {
        let entered = expectation(description: "worker entered"), completed = expectation(description: "completed")
        let gate = DispatchSemaphore(value: 0)
        var permitted = true
        let query = CaptureElementQuery(timeout: .seconds(1), permitted: { permitted }, reader: { _ in
            entered.fulfill(); _ = gate.wait(timeout: .now() + 2)
            return .init(window: CGRect(x: 0, y: 0, width: 100, height: 100), rectangles: [])
        })
        query.start(at: .zero) { result in XCTAssertNil(result); completed.fulfill() }
        await fulfillment(of: [entered], timeout: 1)
        permitted = false; gate.signal(); await fulfillment(of: [completed], timeout: 1)
    }
    @MainActor func testCoordinatorShowsFrozenFrameWhileElementReaderIsBlocked() async throws {
        _ = NSApplication.shared
        let gate = DispatchSemaphore(value: 0), entered = expectation(description: "reader entered")
        let query = CaptureElementQuery(timeout: .seconds(1), permitted: { true }, reader: { _ in
            XCTAssertFalse(Thread.isMainThread); entered.fulfill(); _ = gate.wait(timeout: .now() + 2); return nil
        })
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let rect = CGRect(x: (NSScreen.screens.map { $0.frame.maxX }.max() ?? 0) + 100, y: 0, width: 400, height: 300)
        let coordinator = ScreenshotCoordinator(captureFrames: { [.init(displayID: 999, rect: rect, image: image)] }, allowed: { true }, elementQuery: query)
        defer { gate.signal(); coordinator.stop() }
        coordinator.start(); coordinator.capture()
        await fulfillment(of: [entered], timeout: 1)
        for _ in 0..<20 {
            if NSApp.windows.contains(where: { ($0.contentView as? CaptureCanvas)?.image === image }) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let panel = try XCTUnwrap(NSApp.windows.first { ($0.contentView as? CaptureCanvas)?.image === image })
        XCTAssertTrue(panel.isVisible) // A waiting AX worker cannot hold up pixel presentation.
    }
}
