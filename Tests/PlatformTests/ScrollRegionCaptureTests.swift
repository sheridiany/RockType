import AppKit
import XCTest
@testable import RoarkTPlatform

final class ScrollRegionCaptureTests: XCTestCase {
    private func window(_ id: Int, pid: Int, bounds: CGRect) -> [String: Any] {
        [kCGWindowNumber as String: NSNumber(value: id), kCGWindowOwnerPID as String: NSNumber(value: pid),
         kCGWindowLayer as String: NSNumber(value: 0), kCGWindowAlpha as String: NSNumber(value: 1),
         kCGWindowBounds as String: bounds.dictionaryRepresentation]
    }
    @MainActor func testTargetExcludesSelfAndRejectsRegionCrossingForegroundWindowBoundary() {
        let large = CGRect(x: -400, y: -200, width: 600, height: 400)
        let small = CGRect(x: -200, y: -100, width: 200, height: 180)
        let list = [window(1, pid: 10, bounds: large), window(2, pid: 20, bounds: small), window(3, pid: 30, bounds: large)]
        let chosen = ScrollRegionCapture.target(in: list, selection: CGRect(x: -180, y: -80, width: 80, height: 60), ownPID: 10)
        XCTAssertEqual(chosen?.windowID, 2); XCTAssertEqual(chosen?.pid, 20)
        // Its center is in the front window, but it crosses its edges: must not sample the window behind.
        XCTAssertNil(ScrollRegionCapture.target(in: list, selection: CGRect(x: -250, y: -80, width: 200, height: 60), ownPID: 10))
        XCTAssertNil(ScrollRegionCapture.target(in: [list[0]], selection: small, ownPID: 10))
    }
    @MainActor func testCropUsesLogicalCoordinatesOnLeftAboveAndBelowDisplays() {
        for display in [CGRect(x: -1920, y: 0, width: 1920, height: 1080), CGRect(x: 0, y: 1080, width: 1920, height: 1080), CGRect(x: 1920, y: -400, width: 1920, height: 1080)] {
            let selection = CGRect(x: display.minX + 40, y: display.maxY - 230, width: 320, height: 200)
            XCTAssertEqual(ScrollRegionCapture.sourceRect(selection: selection, display: display), CGRect(x: 40, y: 30, width: 320, height: 200))
        }
    }

}
