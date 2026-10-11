import AppKit
import XCTest
import RoarkTPlatform
@testable import RoarkTApp

final class WindowSelectionTests: XCTestCase {
    private func info(_ rect: CGRect, pid: Int = 42, layer: Int = 0, alpha: Double = 1, owner: String = "Synthetic") -> [String: Any] {
        [kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer,
         kCGWindowAlpha as String: alpha, kCGWindowOwnerName as String: owner,
         kCGWindowBounds as String: rect.dictionaryRepresentation]
    }
    func testFiltersAndClipsNegativeOriginDisplayPreservingStackOrder() {
        let front = CGRect(x: -120, y: -80, width: 200, height: 200)
        let back = CGRect(x: -300, y: -50, width: 200, height: 100)
        let windows = [info(front), info(back), info(front, pid: 7), info(front, layer: 25),
            info(front, alpha: 0), info(front, owner: "Dock"), info(CGRect(x: 0, y: 0, width: 20, height: 20)),
            info(CGRect(x: 2000, y: 0, width: 100, height: 100))]
        XCTAssertEqual(CaptureWindowGeometry.rectangles(windows,
            display: CGRect(x: -400, y: 700, width: 400, height: 300), desktopTop: 900, ownPID: 7), [
                CGRect(x: 280, y: 20, width: 120, height: 200),
                CGRect(x: 100, y: 50, width: 200, height: 100)
            ])
    }
    @MainActor func testClickChoosesFrontWindowWhileDragRemainsFreeform() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let front = CGRect(x: 100, y: 100, width: 200, height: 200)
        let canvas = CaptureCanvas(frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            image: try XCTUnwrap(context.makeImage()), windows: [front, CGRect(x: 50, y: 50, width: 400, height: 400)])
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        canvas.updateHover(at: CGPoint(x: 150, y: 150))
        XCTAssertTrue(canvas.selection.isEmpty)
        canvas.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 150, y: 150)))
        canvas.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 150, y: 150)))
        XCTAssertEqual(canvas.selection, front)
        canvas.selection = .zero
        canvas.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 150, y: 150)))
        canvas.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 350, y: 250)))
        canvas.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 350, y: 250)))
        XCTAssertEqual(canvas.selection, CGRect(x: 150, y: 150, width: 200, height: 100))
    }
}
