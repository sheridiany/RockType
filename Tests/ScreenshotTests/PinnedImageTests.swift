import XCTest
import AppKit
@testable import RoarkTApp

final class PinnedImageTests: XCTestCase {
    func testZoomLimitsAndOffscreenPlacement() {
        XCTAssertEqual(PinnedImageGeometry.scale(0), 0.1)
        XCTAssertEqual(PinnedImageGeometry.scale(100), 4)
        XCTAssertEqual(PinnedImageGeometry.scale(.nan), 1)
        let screen = CGRect(x: -1200, y: 40, width: 1200, height: 800)
        let original = CGRect(x: -100, y: 700, width: 400, height: 200)
        let fit = PinnedImageGeometry.fitted(original, in: screen)
        XCTAssertTrue(screen.contains(fit))
        XCTAssertEqual(fit.size, original.size)
        let zoom = PinnedImageGeometry.zoom(fit, base: original.size, scale: 100, in: screen)
        XCTAssertTrue(screen.contains(zoom))
        XCTAssertEqual(zoom.width / zoom.height, 2)
        let small = PinnedImageGeometry.zoom(fit, base: original.size, scale: 0, in: screen)
        XCTAssertEqual(small.width, 40); XCTAssertEqual(small.height, 20)
        XCTAssertEqual(small.midX, fit.midX); XCTAssertEqual(small.midY, fit.midY)
    }

    @MainActor func testProtectedPinCreatesNoPanel() throws {
        let controller = PinnedImageController(allowed: { false }, copyImage: { _ in XCTFail("Protected copy") })
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        XCTAssertFalse(controller.pin(try XCTUnwrap(bitmap.cgImage), at: CGRect(x: 0, y: 0, width: 8, height: 4)))
        XCTAssertTrue(controller.panels.isEmpty)
    }
}
