import XCTest
import AppKit
@testable import RoarkTApp

final class CompositorTests: XCTestCase {
    func testRetinaCropAndAnnotationPixels() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 160, bitsPerComponent: 8, bytesPerRow: 800,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 200, height: 160))
        let image = try XCTUnwrap(context.makeImage())
        let annotation = ScreenshotAnnotation(tool: .rectangle, points: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)], color: .red, width: 2)
        let result = try XCTUnwrap(ScreenshotCompositor.render(image: image, size: CGSize(width: 100, height: 80),
            selection: CGRect(x: 10, y: 10, width: 60, height: 50), annotations: [annotation]))
        XCTAssertEqual(result.width, 120); XCTAssertEqual(result.height, 100)
        let bitmap = NSBitmapImageRep(cgImage: result)
        let border = try XCTUnwrap(bitmap.colorAt(x: 20, y: 30)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(border.redComponent, 0.9); XCTAssertLessThan(border.greenComponent, 0.1)
        let untouched = try XCTUnwrap(bitmap.colorAt(x: 70, y: 70)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(untouched.greenComponent, 0.9)
    }
    func testUndoRedoAndNewBranch() {
        var history = ScreenshotAnnotationHistory()
        history.append(.init(tool: .text, points: [.zero], text: "Synthetic"))
        history.append(.init(tool: .number, points: [.zero]))
        history.undo(); XCTAssertEqual(history.items.count, 1)
        history.redo(); XCTAssertEqual(history.items.last?.tool, .number)
        history.undo(); history.append(.init(tool: .pen, points: [.zero]))
        history.redo(); XCTAssertEqual(history.items.count, 2); XCTAssertEqual(history.items.last?.tool, .pen)
    }
}
