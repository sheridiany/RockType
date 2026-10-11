import XCTest
import CoreGraphics
@testable import RoarkTPlatform

final class CaptureAccessibilityTests: XCTestCase {
    private func window(_ pid: Int32, _ rect: CGRect, layer: Int = 0, alpha: Double = 1, owner: String = "Synthetic") -> [String: Any] {
        [kCGWindowOwnerPID as String: NSNumber(value: pid), kCGWindowLayer as String: NSNumber(value: layer),
         kCGWindowAlpha as String: NSNumber(value: alpha), kCGWindowOwnerName as String: owner,
         kCGWindowBounds as String: rect.dictionaryRepresentation]
    }
    func testTopmostForeignWindowExcludesOwnTransparentDesktopAndOverlayWindows() {
        let rect = CGRect(x: -400, y: -200, width: 400, height: 300), point = CGPoint(x: -300, y: -100)
        let candidates = [window(7, rect), window(8, rect, alpha: 0), window(9, rect, layer: 24), window(10, rect, owner: "Dock"), window(11, rect), window(12, rect)]
        let target = CaptureAccessibility.target(at: point, windows: candidates, ownPID: 7)
        XCTAssertEqual(target?.pid, 11); XCTAssertEqual(target?.window, rect)
        XCTAssertNil(CaptureAccessibility.target(at: CGPoint(x: 20, y: 20), windows: candidates, ownPID: 7))
        XCTAssertNil(CaptureAccessibility.target(at: point, windows: [window(7, rect)], ownPID: 7))
    }
    @MainActor func testNoAXFallsBackButSecureOrUnknownFocusStillBlocksCapture() {
        XCTAssertTrue(ScreenCapture.permitsCapture(.noPermission))
        XCTAssertTrue(ScreenCapture.permitsCapture(.allowed))
        XCTAssertFalse(ScreenCapture.permitsCapture(.secureInput))
        XCTAssertFalse(ScreenCapture.permitsCapture(.unavailable))
    }
}
