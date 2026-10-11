import AppKit
import XCTest
@testable import RoarkTApp

final class CanvasTests: XCTestCase {
    @MainActor func testMovingSelectionKeepsFrozenImageAndToolbar() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let canvas = CaptureCanvas(frame: CGRect(x: 0, y: 0, width: 800, height: 600), image: image)
        canvas.selection = CGRect(x: 100, y: 100, width: 200, height: 100)
        let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 124))
        canvas.keyDown(with: key)
        let toolbar = try XCTUnwrap(canvas.subviews.last)
        let frozen = try XCTUnwrap(canvas.layer?.sublayers?.first)
        for _ in 0..<20 { canvas.keyDown(with: key) }
        XCTAssertTrue(canvas.subviews.last === toolbar)
        XCTAssertTrue(canvas.layer?.sublayers?.first === frozen)
        XCTAssertTrue((frozen.contents as AnyObject?) === image)
        XCTAssertEqual(canvas.selection, CGRect(x: 121, y: 100, width: 200, height: 100))
    }
}
