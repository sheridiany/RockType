import AppKit
import XCTest
import SwiftUI
@testable import RoarkTApp

final class EraserTests: XCTestCase {
    private func sweep(_ x: CGFloat, _ y: CGFloat, to end: CGPoint? = nil, radius: CGFloat = 10) -> ScreenshotEraser.Sweep {
        .init(from: CGPoint(x: x, y: y), to: end ?? CGPoint(x: x, y: y), radius: radius)
    }
    func testSparseStrokeCutsAtExactIntersectionsAndPreservesStyle() throws {
        for tool in [ScreenshotTool.pen, .highlighter] {
            let original = ScreenshotAnnotation(tool: tool, points: [.zero, CGPoint(x: 100, y: 0)], color: .blue, width: 4)
            let result = try ScreenshotEraser.erase([original], sweeps: [sweep(50, -100, to: CGPoint(x: 50, y: 100))])
            XCTAssertEqual(result.items.count, 2); XCTAssertTrue(result.removed.isEmpty)
            let edge: CGFloat = tool == .pen ? 38 : 40
            XCTAssertEqual(result.items[0].points, [.zero, CGPoint(x: edge, y: 0)])
            XCTAssertEqual(result.items[1].points, [CGPoint(x: 100 - edge, y: 0), CGPoint(x: 100, y: 0)])
            XCTAssertTrue(result.items.allSatisfy { $0.color == original.color && $0.width == 4 && $0.tool == tool })
        }
    }
    func testHighlighterGrazingItsEdgeStillCutsAndEmptyBendKeepsDuplicatePoints() throws {
        let points = [CGPoint.zero, CGPoint(x: 100, y: 0)]
        let fragments = try ScreenshotEraser.split(points, by: sweep(50, 15), width: 20, roundedCaps: false)
        XCTAssertEqual(fragments.count, 2)
        XCTAssertEqual(try XCTUnwrap(fragments[0].last).x, 50 - sqrt(75), accuracy: 1e-8)
        let bent = [CGPoint.zero, .zero, CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)]
        XCTAssertEqual(try ScreenshotEraser.split(bent, by: sweep(40, 50), width: 4), [bent])
    }
    func testHeadTailWholeAndDotErasure() throws {
        let path = [CGPoint.zero, CGPoint(x: 100, y: 0)]
        XCTAssertEqual(try ScreenshotEraser.split(path, by: sweep(0, 0), width: 4), [[CGPoint(x: 12, y: 0), path[1]]])
        XCTAssertEqual(try ScreenshotEraser.split(path, by: sweep(100, 0), width: 4), [[path[0], CGPoint(x: 88, y: 0)]])
        XCTAssertTrue(try ScreenshotEraser.split(path, by: sweep(-10, 0, to: CGPoint(x: 110, y: 0)), width: 4).isEmpty)
        XCTAssertTrue(try ScreenshotEraser.split([.zero, .zero], by: sweep(0, 0), width: 4).isEmpty)
        XCTAssertEqual(try ScreenshotEraser.split([.zero, .zero], by: sweep(50, 50), width: 4), [[.zero, .zero]])
    }
    func testDiagonalBentAndDuplicatePointPathsKeepUnwipedSegments() throws {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50), CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 0)]
        let fragments = try ScreenshotEraser.split(points, by: sweep(50, 50), width: 4)
        XCTAssertEqual(fragments.count, 2)
        XCTAssertEqual(try XCTUnwrap(fragments[0].last).x, 50 - 12 / sqrt(2), accuracy: 1e-8)
        XCTAssertEqual(fragments[1][0].x, 50 + 12 / sqrt(2), accuracy: 1e-8)
        XCTAssertEqual(fragments[0].first, points.first); XCTAssertEqual(fragments[1].last, points.last)
        XCTAssertTrue(fragments.flatMap { $0 }.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }
    func testShapeOutlinesFilledObjectsAndArrowheadAreHitBySweptCircle() throws {
        for tool in [ScreenshotTool.rectangle, .ellipse] {
            let shape = ScreenshotAnnotation(tool: tool, points: [.zero, CGPoint(x: 100, y: 100)], width: 2)
            XCTAssertFalse(try ScreenshotEraser.hits(shape, sweep: sweep(50, 50, radius: 4)))
            XCTAssertTrue(try ScreenshotEraser.hits(shape, sweep: sweep(-20, 50, to: CGPoint(x: 120, y: 50), radius: 4)))
        }
        let arrow = ScreenshotAnnotation(tool: .arrow, points: [.zero, CGPoint(x: 100, y: 0)], width: 8)
        XCTAssertTrue(try ScreenshotEraser.hits(arrow, sweep: sweep(73, 16, radius: 4)))
        XCTAssertTrue(try ScreenshotEraser.erase([arrow], sweeps: [sweep(73, 16, radius: 4)]).items.isEmpty)
        for tool in [ScreenshotTool.text, .mosaic, .number] {
            let shape = ScreenshotAnnotation(tool: tool, points: [CGPoint(x: 40, y: 40), CGPoint(x: 90, y: 90)], text: "Example", width: 4)
            XCTAssertTrue(try ScreenshotEraser.hits(shape, sweep: sweep(shape.bounds.midX, shape.bounds.midY, radius: 4)))
        }
        let rounded = ScreenshotAnnotation(tool: .rectangle, points: [.zero, CGPoint(x: 100, y: 100)], width: 2)
        XCTAssertFalse(try ScreenshotEraser.hits(rounded, sweep: sweep(0, 0, radius: 0.25)))
    }
    func testNoHitNoMutationAndSweepClipsAtSelection() throws {
        let item = ScreenshotAnnotation(tool: .pen, points: [.zero, CGPoint(x: 100, y: 0)], width: 4)
        XCTAssertEqual(try ScreenshotEraser.erase([item], sweeps: [sweep(50, 30)]).items, [item])
        let clipped = try XCTUnwrap(sweep(-20, 50, to: CGPoint(x: 120, y: 50)).clipped(to: CGRect(x: 0, y: 0, width: 100, height: 100)))
        XCTAssertEqual(clipped.from, CGPoint(x: 0, y: 50)); XCTAssertEqual(clipped.to, CGPoint(x: 100, y: 50))
        XCTAssertNil(sweep(-20, -20, to: CGPoint(x: -10, y: -10)).clipped(to: CGRect(x: 0, y: 0, width: 100, height: 100)))
    }
    @MainActor private func canvas() throws -> CaptureCanvas {
        let c = try XCTUnwrap(CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        c.setFillColor(NSColor.white.cgColor); c.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        let canvas = CaptureCanvas(frame: CGRect(x: 0, y: 0, width: 800, height: 600), image: try XCTUnwrap(c.makeImage()))
        canvas.allowed = { true }; canvas.roundedCorners = false
        canvas.restore(CGRect(x: 20, y: 20, width: 700, height: 460)); return canvas
    }
    @MainActor private func mouse(_ canvas: CaptureCanvas, _ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) throws {
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(CGPoint(x: x, y: y), to: nil),
            modifierFlags: .option, timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        switch type {
        case .leftMouseDown: canvas.mouseDown(with: event)
        case .leftMouseDragged: canvas.mouseDragged(with: event)
        case .mouseMoved: canvas.mouseMoved(with: event)
        default: canvas.mouseUp(with: event)
        }
    }
    private func key(_ code: UInt16, text: String, flags: NSEvent.ModifierFlags = .command) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
            context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
    }
    @MainActor private func draw(_ canvas: CaptureCanvas, x: CGFloat, tool: ScreenshotTool = .rectangle) throws {
        canvas.selectTool(tool)
        try mouse(canvas, .leftMouseDown, x, 100); try mouse(canvas, .leftMouseDragged, x + 80, 180)
        try mouse(canvas, .leftMouseUp, x + 80, 180)
    }
    @MainActor private func settle(_ canvas: CaptureCanvas) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while canvas.isErasing && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertFalse(canvas.isErasing)
    }
    @MainActor func testDragIsOneUndoAndFastFollowingGesturesStayOrdered() async throws {
        let canvas = try canvas(); try draw(canvas, x: 100); try draw(canvas, x: 300)
        let originals = canvas.annotations
        canvas.selectTool(.eraser)
        try mouse(canvas, .leftMouseDown, 140, 100)
        try mouse(canvas, .leftMouseDragged, 140, 140); try mouse(canvas, .leftMouseUp, 140, 140)
        try mouse(canvas, .leftMouseDown, 340, 100)
        try mouse(canvas, .leftMouseDragged, 340, 140); try mouse(canvas, .leftMouseUp, 340, 140)
        XCTAssertEqual(canvas.subviews.compactMap { $0 as? CaptureEraserEffects }.first?.center, CGPoint(x: 340, y: 140))
        canvas.keyDown(with: try key(6, text: "z")) // Queued behind the second drag, never behind only its first sample.
        try await settle(canvas)
        XCTAssertEqual(canvas.annotations, [originals[1]])
        canvas.keyDown(with: try key(6, text: "z")); XCTAssertEqual(canvas.annotations, originals)
        canvas.keyDown(with: try key(6, text: "z", flags: [.command, .shift]))
        XCTAssertEqual(canvas.annotations, [originals[1]])
        canvas.keyDown(with: try key(6, text: "z", flags: [.command, .shift])); XCTAssertTrue(canvas.annotations.isEmpty)
    }
    @MainActor func testOneDragRemovesSeveralShapesAndSplitsPenInOneUndo() async throws {
        let canvas = try canvas(); try draw(canvas, x: 100); try draw(canvas, x: 300); try draw(canvas, x: 500, tool: .pen)
        let originals = canvas.annotations; canvas.selectTool(.eraser)
        try mouse(canvas, .leftMouseDown, 50, 140)
        let toolbar = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSHostingView<CaptureToolbar> }.first)
        toolbar.rootView.changeStyle(.init(width: 48)) // Resizing the eraser while held must not split the undo transaction.
        try mouse(canvas, .leftMouseDragged, 650, 140)
        try mouse(canvas, .leftMouseUp, 650, 140); try await settle(canvas)
        XCTAssertEqual(canvas.annotations.count, 2); XCTAssertTrue(canvas.annotations.allSatisfy { $0.tool == .pen })
        canvas.keyDown(with: try key(6, text: "z")); XCTAssertEqual(canvas.annotations, originals)
    }
    @MainActor func testExportWaitsForEraseAndContainsNoGhostTrailHoverOrCursor() async throws {
        let canvas = try canvas(); try draw(canvas, x: 100); canvas.selectTool(.eraser)
        var exported: CGImage?, hadGhost = false
        canvas.onComplete = { image in
            exported = image
            hadGhost = canvas.subviews.compactMap { $0 as? CaptureEraserEffects }.first?.ghosts.isEmpty == false
        }
        try mouse(canvas, .leftMouseDown, 140, 100)
        canvas.keyDown(with: try key(8, text: "c"))
        try await settle(canvas)
        XCTAssertTrue(hadGhost)
        let expected = try XCTUnwrap(ScreenshotCompositor.render(image: canvas.image, size: canvas.bounds.size,
            selection: canvas.selection, annotations: []))
        let final = try XCTUnwrap(ScreenshotExport.render(image: expected, pointSize: canvas.selection.size, roundedCorners: false))
        XCTAssertEqual(try XCTUnwrap(exported?.dataProvider?.data) as Data, try XCTUnwrap(final.dataProvider?.data) as Data)
        canvas.onComplete = { _ in }
    }
    @MainActor func testCancellationAndProtectionNeverPublishPendingErasure() async throws {
        let canvas = try canvas(); try draw(canvas, x: 100); let original = canvas.annotations
        canvas.selectTool(.eraser); try mouse(canvas, .leftMouseDown, 140, 100)
        canvas.cancelEraser(); try await Task.sleep(for: .milliseconds(20)); XCTAssertEqual(canvas.annotations, original)
        try mouse(canvas, .leftMouseDown, 140, 100)
        var cancelled = false; canvas.onCancel = { cancelled = true }; canvas.allowed = { false }
        try mouse(canvas, .leftMouseUp, 140, 100); try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(cancelled); XCTAssertEqual(canvas.annotations, original); XCTAssertFalse(canvas.isErasing)
    }
    @MainActor func testHoverRestoresAndWidthIsBounded() async throws {
        let canvas = try canvas(); try draw(canvas, x: 100); canvas.selectTool(.eraser)
        try mouse(canvas, .mouseMoved, 140, 100)
        let surface = try XCTUnwrap(canvas.subviews.compactMap { $0 as? CaptureAnnotationView }.first)
        let deadline = ContinuousClock.now + .seconds(3)
        while surface.hoveredIndices.isEmpty && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertEqual(surface.hoveredIndices, [0])
        try mouse(canvas, .mouseMoved, 250, 250); XCTAssertTrue(surface.hoveredIndices.isEmpty)
        XCTAssertEqual(ScreenshotTool.eraser.style(from: ["eraser": .init(width: 2)]).width, 8)
        XCTAssertEqual(ScreenshotTool.eraser.style(from: ["eraser": .init(width: 100)]).width, 48)
        XCTAssertEqual(ScreenshotTool.eraser.defaultWidth, 24)
        canvas.cancelEraser()
    }
    func testRepresentativeGeometryBatchRecordsTiming() throws {
        let items = (0..<64).map { row in
            ScreenshotAnnotation(tool: .pen, points: (0..<128).map { CGPoint(x: CGFloat($0) * 6, y: CGFloat(row) * 6 + sin(CGFloat($0)) * 2) }, width: 3)
        }
        let start = ContinuousClock.now
        let result = try ScreenshotEraser.erase(items, sweeps: [sweep(380, 0, to: CGPoint(x: 380, y: 400))])
        XCTAssertEqual(result.items.count, 128)
        print("E1 synthetic geometry: 8192 points / 64 strokes / one sweep: \(start.duration(to: .now))")
    }
}
