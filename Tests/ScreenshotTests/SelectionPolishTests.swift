import AppKit
import SwiftUI
import XCTest
@testable import RoarkTApp

final class SelectionPolishTests: XCTestCase {
    @MainActor private func canvas() throws -> CaptureCanvas {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        let canvas = CaptureCanvas(frame: CGRect(x: 0, y: 0, width: 800, height: 600), image: try XCTUnwrap(ctx.makeImage()))
        canvas.allowed = { true }; canvas.restore(CGRect(x: 100, y: 100, width: 400, height: 250))
        return canvas
    }
    private func key(_ code: UInt16, _ text: String, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
            context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
    }
    @MainActor private func click(_ canvas: CaptureCanvas, at point: CGPoint, count: Int = 1) throws {
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(point, to: nil), modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: count, pressure: 1))
        canvas.mouseDown(with: down); canvas.mouseUp(with: down)
    }
    @MainActor func testCShiftCCommandCAndSaveDispatchWithProtection() throws {
        let canvas = try canvas(); canvas.updateHover(at: CGPoint(x: 200, y: 200))
        var actions: [String] = []
        canvas.onCopyColor = { XCTAssertEqual($0, "#00FF00"); actions.append("color") }
        canvas.onOCRCopy = { image in
            XCTAssertGreaterThan(NSBitmapImageRep(cgImage: image).colorAt(x: 0, y: 0)!.alphaComponent, 0.99)
            actions.append("ocr")
        }
        canvas.onComplete = { image in
            XCTAssertLessThan(NSBitmapImageRep(cgImage: image).colorAt(x: 0, y: 0)!.alphaComponent, 0.01)
            actions.append("image")
        }
        canvas.onSaveAs = { _ in actions.append("saveAs") }
        canvas.onSave = { _ in actions.append("quickSave") }
        canvas.onCancel = { actions.append("cancel") }
        canvas.keyDown(with: try key(8, "c"))
        canvas.keyDown(with: try key(8, "C", .shift))
        XCTAssertTrue(canvas.performKeyEquivalent(with: try key(8, "c", .command)))
        XCTAssertTrue(canvas.performKeyEquivalent(with: try key(1, "s", .command)))
        canvas.keyDown(with: try key(36, "\r", .shift))
        XCTAssertEqual(actions, ["color", "ocr", "image", "saveAs", "quickSave"])
        canvas.allowed = { false }; canvas.keyDown(with: try key(8, "c"))
        XCTAssertEqual(actions.last, "cancel"); XCTAssertNil(canvas.sampledColor)
    }
    @MainActor func testDoubleClickCopiesEmptySelectionButTextDoubleClickStillEdits() throws {
        let canvas = try canvas()
        var copies = 0; canvas.onComplete = { _ in copies += 1 }
        try click(canvas, at: CGPoint(x: 300, y: 220), count: 2)
        XCTAssertEqual(copies, 1)
        canvas.selectTool(.text)
        try click(canvas, at: CGPoint(x: 150, y: 150))
        let editor = try XCTUnwrap(canvas.subviews.compactMap { $0 as? CaptureTextView }.first)
        editor.insertText("Synthetic", replacementRange: NSRange(location: NSNotFound, length: 0))
        canvas.finishTextEditing(); canvas.selectTool(nil)
        try click(canvas, at: CGPoint(x: 152, y: 152), count: 2)
        XCTAssertTrue(canvas.isEditingText); XCTAssertEqual(copies, 1)
        XCTAssertFalse(canvas.performKeyEquivalent(with: try key(1, "s", .command)))
        canvas.keyDown(with: try key(8, "C", .shift))
        XCTAssertTrue(canvas.isEditingText); XCTAssertEqual(copies, 1)
    }
    @MainActor func testMagnifierAvoidsToolbarWhenPointerIsAlongItsRightEdge() throws {
        let canvas = try canvas()
        canvas.updateHover(at: CGPoint(x: 700, y: 370))
        let toolbar = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSHostingView<CaptureToolbar> }.first)
        let lens = try XCTUnwrap(canvas.subviews.compactMap { $0 as? CaptureMagnifier }.first)
        XCTAssertFalse(lens.isHidden)
        XCTAssertFalse(lens.frame.intersects(toolbar.frame))
        XCTAssertTrue(canvas.bounds.contains(lens.frame))
    }
    @MainActor func testKeyEdgesAndHoverKeepFrozenLayerToolbarAndAnnotations() throws {
        let canvas = try canvas()
        let frozen = try XCTUnwrap(canvas.layer?.sublayers?.first)
        let toolbar = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSHostingView<CaptureToolbar> }.first)
        let annotations = try XCTUnwrap(canvas.subviews.compactMap { $0 as? CaptureAnnotationView }.first)
        annotations.needsDisplay = false
        for i in 0..<100 {
            canvas.updateHover(at: CGPoint(x: 200 + i, y: 200))
            XCTAssertEqual(canvas.sampledColor, "#00FF00")
        }
        canvas.keyDown(with: try key(123, "", .option))
        XCTAssertEqual(canvas.selection, CGRect(x: 99, y: 100, width: 401, height: 250))
        XCTAssertTrue(canvas.performKeyEquivalent(with: try key(125, "", [.command, .shift])))
        XCTAssertEqual(canvas.selection, CGRect(x: 99, y: 100, width: 401, height: 260))
        XCTAssertTrue(canvas.layer?.sublayers?.first === frozen)
        XCTAssertTrue((frozen.contents as AnyObject?) === canvas.image)
        XCTAssertTrue(canvas.subviews.contains { $0 === toolbar })
        XCTAssertFalse(annotations.needsDisplay)
    }
}
