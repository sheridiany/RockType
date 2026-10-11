import XCTest
@testable import RoarkTApp
import RoarkTPlatform

final class CaptureTests: XCTestCase {
    func testReverseDragAndDisplayBoundary() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        XCTAssertEqual(CaptureGeometry.selection(from: CGPoint(x: 150, y: 100), to: CGPoint(x: -20, y: 20), bounds: bounds), CGRect(x: 0, y: 20, width: 150, height: 80))
        XCTAssertEqual(CaptureGeometry.moved(CGRect(x: 10, y: 10, width: 100, height: 50), by: CGSize(width: 999, height: -20), bounds: bounds), CGRect(x: 200, y: 0, width: 100, height: 50))
    }
    func testAllHandlesRemainBoundedAndPositive() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        for h in ScreenshotHandle.allCases {
            for delta in [CGSize(width: -1000, height: -1000), CGSize(width: 1000, height: 1000)] {
                let result = CaptureGeometry.resized(CGRect(x: 50, y: 50, width: 100, height: 80), handle: h, by: delta, bounds: bounds)
                XCTAssertTrue(bounds.contains(result)); XCTAssertGreaterThanOrEqual(result.width, 1); XCTAssertGreaterThanOrEqual(result.height, 1)
            }
        }
    }
    @MainActor func testCancelDropsLateCaptureAndDoesNotComplete() async {
        var continuation: CheckedContinuation<[ScreenCapture.Frame], any Error>?
        let coordinator = ScreenshotCoordinator(captureFrames: {
            try await withCheckedThrowingContinuation { continuation = $0 }
        }, allowed: { true }, elementQuery: CaptureElementQuery(permitted: { false }))
        var completions = 0
        coordinator.onSelection = { _ in completions += 1 }
        coordinator.start(); coordinator.capture()
        for _ in 0..<10 { await Task.yield() }
        coordinator.cancel(); continuation?.resume(returning: [])
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(completions, 0)
        coordinator.stop()
    }
}
