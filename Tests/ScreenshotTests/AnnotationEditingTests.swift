import AppKit
import SwiftUI
import XCTest
@testable import RoarkTApp

final class AnnotationEditingTests: XCTestCase {
    @MainActor private func canvas() throws -> CaptureCanvas {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        let canvas = CaptureCanvas(frame: CGRect(x: 0, y: 0, width: 800, height: 600), image: try XCTUnwrap(ctx.makeImage()))
        canvas.allowed = { true }; canvas.restore(CGRect(x: 20, y: 20, width: 700, height: 460))
        return canvas
    }
    @MainActor private func mouse(_ canvas: CaptureCanvas, _ type: NSEvent.EventType, _ point: CGPoint,
                                  _ flags: NSEvent.ModifierFlags = []) throws {
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: flags,
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        switch type {
        case .leftMouseDown: canvas.mouseDown(with: event)
        case .leftMouseDragged: canvas.mouseDragged(with: event)
        default: canvas.mouseUp(with: event)
        }
    }
    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], text: String = "") throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
    }
    @MainActor private func draw(_ canvas: CaptureCanvas, tool: ScreenshotTool = .rectangle) throws {
        canvas.selectTool(tool)
        try mouse(canvas, .leftMouseDown, CGPoint(x: 100, y: 100))
        try mouse(canvas, .leftMouseDragged, CGPoint(x: 200, y: 150))
        try mouse(canvas, .leftMouseUp, CGPoint(x: 200, y: 150))
    }
    @MainActor func testMoveResizeDeleteAndUndoAreAtomicAndDoNotChangeCrop() throws {
        let canvas = try canvas(); let crop = canvas.selection
        try draw(canvas)
        canvas.selectTool(nil)
        try mouse(canvas, .leftMouseDown, CGPoint(x: 150, y: 100))
        try mouse(canvas, .leftMouseDragged, CGPoint(x: 160, y: 120))
        try mouse(canvas, .leftMouseDragged, CGPoint(x: 170, y: 130))
        try mouse(canvas, .leftMouseUp, CGPoint(x: 170, y: 130))
        XCTAssertEqual(canvas.annotations[0].rect, CGRect(x: 120, y: 130, width: 100, height: 50))
        XCTAssertEqual(canvas.selection, crop)
        XCTAssertTrue(canvas.performKeyEquivalent(with: try key(6, flags: .command, text: "z")))
        XCTAssertEqual(canvas.annotations[0].rect, CGRect(x: 100, y: 100, width: 100, height: 50))
        // Reselect, then resize with the bottom-right handle.
        try mouse(canvas, .leftMouseDown, CGPoint(x: 150, y: 100))
        try mouse(canvas, .leftMouseUp, CGPoint(x: 150, y: 100))
        try mouse(canvas, .leftMouseDown, CGPoint(x: 200, y: 150))
        try mouse(canvas, .leftMouseDragged, CGPoint(x: 240, y: 180))
        try mouse(canvas, .leftMouseUp, CGPoint(x: 240, y: 180))
        XCTAssertEqual(canvas.annotations[0].rect, CGRect(x: 100, y: 100, width: 140, height: 80))
        canvas.keyDown(with: try key(117))
        XCTAssertTrue(canvas.annotations.isEmpty)
        XCTAssertTrue(canvas.performKeyEquivalent(with: try key(6, flags: .command, text: "z")))
        XCTAssertEqual(canvas.annotations[0].rect.width, 140)
        XCTAssertEqual(canvas.selection, crop)
        canvas.keyDown(with: try key(51)) // Undo clears selection: no accidental deletion by stale index.
        XCTAssertEqual(canvas.annotations.count, 1)
    }
    @MainActor func testClickDoesNotCreateUndoAndEraserDeletionCanBeUndone() throws {
        let canvas = try canvas(); try draw(canvas)
        canvas.selectTool(nil)
        try mouse(canvas, .leftMouseDown, CGPoint(x: 150, y: 100))
        try mouse(canvas, .leftMouseUp, CGPoint(x: 150, y: 100))
        XCTAssertTrue(canvas.performKeyEquivalent(with: try key(6, flags: .command, text: "z")))
        XCTAssertTrue(canvas.annotations.isEmpty)
        try draw(canvas)
        canvas.keyDown(with: try key(14, text: "e"))
        try mouse(canvas, .leftMouseDown, CGPoint(x: 150, y: 100))
        try mouse(canvas, .leftMouseUp, CGPoint(x: 150, y: 100))
        XCTAssertTrue(canvas.annotations.isEmpty)
        XCTAssertTrue(canvas.performKeyEquivalent(with: try key(6, flags: .command, text: "z")))
        XCTAssertEqual(canvas.annotations.count, 1)
    }
    @MainActor func testShiftToolsAndShiftReturnHaveSeparateRoutes() throws {
        let canvas = try canvas()
        let codes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        for (index, code) in codes.enumerated() {
            canvas.keyDown(with: try key(code, flags: .shift))
            let toolbar = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSHostingView<CaptureToolbar> }.first)
            XCTAssertEqual(toolbar.rootView.tool, ScreenshotTool.allCases[index])
        }
        var saved = false; canvas.onSave = { _ in saved = true }
        canvas.keyDown(with: try key(36, flags: .shift)); XCTAssertTrue(saved)
        XCTAssertNil(ScreenshotTool.shortcut(keyCode: 36))
    }
    @MainActor func testConstrainedDrawingAndSelectedArrowNudge() throws {
        let canvas = try canvas(); canvas.selectTool(.ellipse)
        try mouse(canvas, .leftMouseDown, CGPoint(x: 100, y: 100))
        try mouse(canvas, .leftMouseDragged, CGPoint(x: 160, y: 130), .shift)
        try mouse(canvas, .leftMouseUp, CGPoint(x: 160, y: 130), .shift)
        XCTAssertEqual(canvas.annotations[0].rect.size, CGSize(width: 60, height: 60))
        canvas.selectTool(nil)
        try mouse(canvas, .leftMouseDown, CGPoint(x: 130, y: 100))
        try mouse(canvas, .leftMouseUp, CGPoint(x: 130, y: 100))
        let crop = canvas.selection
        canvas.keyDown(with: try key(124))
        XCTAssertEqual(canvas.annotations[0].rect.minX, 101)
        XCTAssertEqual(canvas.selection, crop)
    }
    @MainActor func testOverlappingAnnotationsSelectTopmostAndRestyleWithUndo() throws {
        let canvas = try canvas(); try draw(canvas)
        canvas.selectTool(.line)
        try mouse(canvas, .leftMouseDown, CGPoint(x: 150, y: 100), .option)
        try mouse(canvas, .leftMouseDragged, CGPoint(x: 240, y: 100), .option)
        try mouse(canvas, .leftMouseUp, CGPoint(x: 240, y: 100), .option)
        XCTAssertEqual(canvas.annotations.count, 2)
        canvas.selectTool(nil)
        try mouse(canvas, .leftMouseDown, CGPoint(x: 170, y: 100))
        try mouse(canvas, .leftMouseUp, CGPoint(x: 170, y: 100))
        XCTAssertEqual(canvas.selectedAnnotation, 1)
        let toolbar = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSHostingView<CaptureToolbar> }.first)
        XCTAssertEqual(toolbar.rootView.tool, .line)
        toolbar.rootView.changeStyle(.init(colorHex: "388BEB", width: 12))
        XCTAssertEqual(canvas.annotations[1].width, 12)
        XCTAssertEqual(canvas.annotations[0].width, 5)
        XCTAssertTrue(canvas.performKeyEquivalent(with: try key(6, flags: .command, text: "z")))
        XCTAssertEqual(canvas.annotations[1].width, 5)
        XCTAssertEqual(canvas.toolStyles["line"]?.width, 12) // Undo content; keep the chosen tool preference.
    }
    @MainActor func testWheelChangesOnlyActiveToolAndKeepsTextSizeIndependent() throws {
        let canvas = try canvas(); canvas.selectTool(.arrow)
        let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 2, wheel2: 0, wheel3: 0))
        canvas.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: cg)))
        XCTAssertEqual(canvas.toolStyles["arrow"]?.width, 6)
        canvas.selectTool(.text)
        let toolbar = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSHostingView<CaptureToolbar> }.first)
        XCTAssertEqual(toolbar.rootView.style.width, 17)
        canvas.allowed = { false }
        canvas.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: cg)))
        XCTAssertNil(canvas.toolStyles["text"])
    }
    @MainActor func testEmptyShapeClickDoesNotConsumeUndo() throws {
        let canvas = try canvas(); canvas.selectTool(.rectangle)
        try mouse(canvas, .leftMouseDown, CGPoint(x: 100, y: 100))
        try mouse(canvas, .leftMouseUp, CGPoint(x: 100, y: 100))
        XCTAssertTrue(canvas.annotations.isEmpty)
        let toolbar = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSHostingView<CaptureToolbar> }.first)
        XCTAssertFalse(toolbar.rootView.canUndo)
    }
    func testNoOpReplacementPreservesUndoAndMosaicSizeChangesExport() throws {
        var history = ScreenshotAnnotationHistory()
        let mark = ScreenshotAnnotation(tool: .rectangle, points: [.zero, CGPoint(x: 30, y: 30)])
        history.append(mark); history.replace(at: 0, with: mark); history.undo()
        XCTAssertTrue(history.items.isEmpty)
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 80, height: 80, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for x in 0..<80 {
            ctx.setFillColor(CGColor(gray: CGFloat(x) / 80, alpha: 1))
            ctx.fill(CGRect(x: x, y: 0, width: 1, height: 80))
        }
        let image = try XCTUnwrap(ctx.makeImage())
        func render(width: CGFloat) throws -> Data {
            let output = try XCTUnwrap(ScreenshotCompositor.render(image: image, size: CGSize(width: 80, height: 80),
                selection: CGRect(x: 0, y: 0, width: 80, height: 80),
                annotations: [.init(tool: .mosaic, points: [.zero, CGPoint(x: 80, y: 80)], width: width)]))
            return try XCTUnwrap(NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:]))
        }
        XCTAssertNotEqual(try render(width: 4), try render(width: 20))
    }
    func testConstraintSurvivesBoundaryInAllQuadrants() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 80), origin = CGPoint(x: 50, y: 40)
        for target in [CGPoint(x: 500, y: 100), CGPoint(x: -500, y: 100), CGPoint(x: -500, y: -100), CGPoint(x: 500, y: -100)] {
            let square = ScreenshotAnnotation.constrainedEnd(from: origin, to: target, tool: .rectangle, within: bounds)
            XCTAssertEqual(abs(square.x - origin.x), abs(square.y - origin.y), accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(square.x, 0); XCTAssertLessThanOrEqual(square.x, 100)
            XCTAssertGreaterThanOrEqual(square.y, 0); XCTAssertLessThanOrEqual(square.y, 80)
            let line = ScreenshotAnnotation.constrainedEnd(from: origin, to: target, tool: .arrow, within: bounds)
            let eighths = atan2(line.y - origin.y, line.x - origin.x) / (.pi / 4)
            XCTAssertEqual(eighths, eighths.rounded(), accuracy: 0.001)
        }
    }
    func testHitTestingUsesStrokesAndAllFreehandPoints() {
        let rectangle = ScreenshotAnnotation(tool: .rectangle, points: [CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 110)])
        XCTAssertFalse(rectangle.contains(CGPoint(x: 60, y: 60)))
        XCTAssertTrue(rectangle.contains(CGPoint(x: 60, y: 12)))
        let pen = ScreenshotAnnotation(tool: .pen, points: [CGPoint(x: 10, y: 10), CGPoint(x: 80, y: 90), CGPoint(x: 12, y: 12)])
        XCTAssertTrue(pen.contains(CGPoint(x: 80, y: 90)))
        XCTAssertFalse(pen.contains(CGPoint(x: 80, y: 15)))
        XCTAssertEqual(pen.bounds.maxY, 90)
    }
    func testResizePreservesReversedArrowDirectionAndTextTypography() {
        let arrow = ScreenshotAnnotation(tool: .arrow, points: [CGPoint(x: 100, y: 100), CGPoint(x: 20, y: 20)])
        let scaled = arrow.resized(to: CGRect(x: 10, y: 10, width: 160, height: 160))
        XCTAssertEqual(scaled.points, [CGPoint(x: 170, y: 170), CGPoint(x: 10, y: 10)])
        let text = ScreenshotAnnotation(tool: .text, points: [CGPoint(x: 10, y: 10)], text: "Synthetic")
        let enlarged = text.resized(to: CGRect(origin: text.bounds.origin, size: CGSize(width: text.bounds.width * 2, height: text.bounds.height * 2)))
        XCTAssertEqual(enlarged.fontSize, 34)
        XCTAssertEqual(ScreenshotText.attributes(for: enlarged)[.strokeColor] as? NSColor, .white)
        XCTAssertEqual(ScreenshotText.attributes(for: enlarged)[.strokeWidth] as? Int, -3)
    }
    func testHighlighterExportIsTranslucentAndRectangleHasRoundedCorner() throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 120, height: 100, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 100))
        let image = try XCTUnwrap(ctx.makeImage())
        let marks = [ScreenshotAnnotation(tool: .highlighter, points: [CGPoint(x: 10, y: 70), CGPoint(x: 100, y: 70)], color: .red, width: 20),
                     ScreenshotAnnotation(tool: .rectangle, points: [CGPoint(x: 20, y: 10), CGPoint(x: 80, y: 45)], color: .red, width: 2)]
        let output = try XCTUnwrap(ScreenshotCompositor.render(image: image, size: CGSize(width: 120, height: 100),
            selection: CGRect(x: 0, y: 0, width: 120, height: 100), annotations: marks))
        let bitmap = NSBitmapImageRep(cgImage: output)
        let highlighted = try XCTUnwrap(bitmap.colorAt(x: 50, y: 70)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(highlighted.greenComponent, 0.7, accuracy: 0.02)
        let corner = try XCTUnwrap(bitmap.colorAt(x: 20, y: 10)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(corner.greenComponent, 0.98)
        let edge = try XCTUnwrap(bitmap.colorAt(x: 50, y: 10)?.usingColorSpace(.deviceRGB))
        XCTAssertLessThan(edge.greenComponent, 0.1)
    }
}
