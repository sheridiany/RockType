import AppKit
import XCTest
@testable import RoarkTApp

final class OverlayGroupTests: XCTestCase {
    @MainActor private func add(_ group: CaptureOverlayGroup, id: CGDirectDisplayID, screen: CGRect, scale: Int) throws -> CaptureCanvas {
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(screen.width) * scale, height: Int(screen.height) * scale,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let canvas = CaptureCanvas(frame: CGRect(origin: .zero, size: screen.size), image: try XCTUnwrap(context.makeImage()))
        let panel = CapturePanel(captureRect: screen)
        group.add(panel: panel, canvas: canvas, displayID: id)
        return canvas
    }
    @MainActor func testMixedScaleDisplaysRestoreToCorrectCanvasAndKeepIndependentPixels() throws {
        let group = CaptureOverlayGroup(); defer { group.close() }
        let left = try add(group, id: 10, screen: CGRect(x: -800, y: -100, width: 800, height: 600), scale: 1)
        let right = try add(group, id: 20, screen: CGRect(x: 0, y: 0, width: 900, height: 700), scale: 2)
        let crop = CGRect(x: 20, y: 30, width: 200, height: 100)
        left.restore(crop); right.restore(crop)
        XCTAssertEqual(CaptureGeometry.pixels(left.selection, image: left.image, size: left.bounds.size).size, crop.size)
        XCTAssertEqual(CaptureGeometry.pixels(right.selection, image: right.image, size: right.bounds.size).size, CGSize(width: 400, height: 200))
        XCTAssertTrue(group.restore(displayID: 10, rect: CGRect(x: 700, y: 500, width: 300, height: 200)))
        XCTAssertEqual(left.selection, CGRect(x: 700, y: 500, width: 100, height: 100))
        XCTAssertTrue(right.selection.isEmpty)
        let preserved = left.selection
        XCTAssertFalse(group.restore(displayID: 999, rect: crop))
        XCTAssertEqual(left.selection, preserved, "Disconnected display must not erase the active selection")
        group.suspend()
        XCTAssertEqual(group.canvases.count, 2)
        XCTAssertFalse(group.panels.contains { $0.isVisible })
        XCTAssertTrue(group.close()); XCTAssertFalse(group.close())
        XCTAssertTrue(group.canvases.isEmpty)
    }
}
