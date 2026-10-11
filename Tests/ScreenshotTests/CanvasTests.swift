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

extension CanvasTests {
    @MainActor func testCopySaveRestoreKeysAndProtection() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let canvas = CaptureCanvas(frame: CGRect(x: 0, y: 0, width: 400, height: 300),
            image: try XCTUnwrap(context.makeImage()))
        canvas.allowed = { true }
        canvas.restore(CGRect(x: 20, y: 30, width: 100, height: 80))
        var outputs: [String] = []
        canvas.onComplete = { image in
            XCTAssertEqual(image.width, 200); XCTAssertEqual(image.height, 160)
            outputs.append("copy")
        }
        canvas.onSave = { image in
            XCTAssertEqual(image.width, 200); XCTAssertEqual(image.height, 160)
            outputs.append("save")
        }
        canvas.onRestore = { outputs.append("restore") }
        canvas.onCancel = { outputs.append("cancel") }
        func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: code))
        }
        canvas.keyDown(with: try key(36, "\r"))
        XCTAssertTrue(canvas.performKeyEquivalent(with: try key(8, "c", .command)))
        canvas.keyDown(with: try key(36, "\r", .shift))
        canvas.keyDown(with: try key(15, "r"))
        XCTAssertEqual(outputs, ["copy", "copy", "save", "restore"])
        canvas.allowed = { false }
        canvas.keyDown(with: try key(36, "\r", .shift))
        XCTAssertEqual(outputs.last, "cancel")
        XCTAssertEqual(outputs.filter { $0 == "save" }.count, 1)
    }
    func testRestoreClipsToChangedDisplayWithoutNegativeCrop() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        XCTAssertEqual(CaptureGeometry.restored(CGRect(x: 350, y: 250, width: 200, height: 200), bounds: bounds),
            CGRect(x: 350, y: 250, width: 50, height: 50))
        XCTAssertEqual(CaptureGeometry.restored(CGRect(x: 500, y: 400, width: 100, height: 100), bounds: bounds), .zero)
    }
}
