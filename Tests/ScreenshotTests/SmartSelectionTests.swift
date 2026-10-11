import AppKit
import XCTest
import RoarkTPlatform
@testable import RoarkTApp

final class SmartSelectionTests: XCTestCase {
    private let window = CGRect(x: 0, y: 0, width: 400, height: 300)
    private let group = CGRect(x: 30, y: 40, width: 200, height: 120)
    private let leaf = CGRect(x: 50, y: 60, width: 60, height: 30)
    private var snapshot: CaptureAccessibility.Snapshot { .init(window: window, rectangles: [group, leaf, leaf, .null]) }
    func testSmallestHoverParentChildAndPointerChange() {
        var model = CaptureSmartSelection(windows: [window]); model.install(snapshot)
        model.update(at: CGPoint(x: 60, y: 70)); XCTAssertEqual(model.current, leaf)
        model.cycle(parent: true); XCTAssertEqual(model.current, group)
        model.update(at: CGPoint(x: 65, y: 75)); XCTAssertEqual(model.current, group) // Don't reset manually chosen hierarchy on a tiny move.
        model.cycle(parent: true); model.cycle(parent: true); XCTAssertEqual(model.current, window)
        model.cycle(parent: false); model.cycle(parent: false); model.cycle(parent: false); XCTAssertEqual(model.current, leaf)
        model.update(at: CGPoint(x: 200, y: 130)); XCTAssertEqual(model.current, group)
        model.update(at: CGPoint(x: 350, y: 220)); XCTAssertEqual(model.current, window)
        model.update(at: CGPoint(x: 450, y: 220)); XCTAssertNil(model.current)
    }
    func testFallbackAndOcclusionDoNotSelectAnElementBehindAnotherWindow() {
        let front = CGRect(x: 0, y: 0, width: 250, height: 200)
        var model = CaptureSmartSelection(windows: [front, window])
        model.update(at: CGPoint(x: 60, y: 70)); XCTAssertEqual(model.current, front)
        model.install(snapshot); model.update(at: CGPoint(x: 60, y: 70)); XCTAssertEqual(model.current, front)
    }
    func testNegativeAboveAndBelowDisplayCoordinatesStayInLogicalPoints() {
        for screen in [CGRect(x: -400, y: 0, width: 400, height: 300), CGRect(x: 0, y: 300, width: 400, height: 300), CGRect(x: 400, y: -120, width: 400, height: 300)] {
            let top = CGPoint(x: screen.minX, y: 300 - screen.maxY)
            let global = CaptureAccessibility.Snapshot(window: window.offsetBy(dx: top.x, dy: top.y), rectangles: [leaf.offsetBy(dx: top.x, dy: top.y)])
            let local = CaptureSmartSelection.local(global, screen: screen, desktopTop: 300)
            XCTAssertEqual(local.window, window); XCTAssertEqual(local.rectangles, [leaf])
        }
    }
    @MainActor private func canvas(scale: Int = 2) throws -> CaptureCanvas {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 400 * scale, height: 300 * scale, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 400 * scale, height: 300 * scale))
        let canvas = CaptureCanvas(frame: window, image: try XCTUnwrap(ctx.makeImage()), windows: [window])
        canvas.allowed = { true }; canvas.installElements(snapshot); canvas.updateHover(at: CGPoint(x: 60, y: 70))
        return canvas
    }
    private func tab(_ shift: Bool = false) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? .shift : [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
    }
    @MainActor private func mouse(_ canvas: CaptureCanvas, _ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
    @MainActor func testTabWheelAndClickSelectFrozenHierarchyAtRetinaScale() throws {
        let canvas = try canvas()
        XCTAssertEqual(canvas.hoveredSelection, leaf)
        canvas.keyDown(with: try tab()); XCTAssertEqual(canvas.hoveredSelection, group)
        canvas.keyDown(with: try tab(true)); XCTAssertEqual(canvas.hoveredSelection, leaf)
        let wheel = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0))
        canvas.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: wheel)))
        XCTAssertEqual(canvas.hoveredSelection, group)
        canvas.mouseDown(with: try mouse(canvas, .leftMouseDown, at: CGPoint(x: 60, y: 70)))
        canvas.mouseUp(with: try mouse(canvas, .leftMouseUp, at: CGPoint(x: 60, y: 70)))
        XCTAssertEqual(canvas.selection, group)
        var pixels: CGSize?
        canvas.onComplete = { pixels = CGSize(width: $0.width, height: $0.height) }
        let enter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        canvas.keyDown(with: enter)
        XCTAssertEqual(pixels, CGSize(width: 400, height: 240))
        XCTAssertFalse(canvas.performKeyEquivalent(with: try tab())) // Restore AppKit focus navigation after selecting.
    }
    @MainActor func testLargeWheelDeltaDoesNotLeaveAReverseScrollMovingOutward() throws {
        let canvas = try canvas()
        for (delta, expected) in [(Int32(1000), window), (Int32(-1), group)] {
            let wheel = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0))
            canvas.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: wheel)))
            XCTAssertEqual(canvas.hoveredSelection, expected)
        }
    }
    @MainActor func testLateSnapshotDoesNotOverrideDragOrCompletedSelection() throws {
        let canvas = try canvas()
        canvas.mouseDown(with: try mouse(canvas, .leftMouseDown, at: CGPoint(x: 60, y: 70)))
        canvas.installElements(.init(window: window, rectangles: [CGRect(x: 0, y: 0, width: 100, height: 100)]))
        canvas.mouseDragged(with: try mouse(canvas, .leftMouseDragged, at: CGPoint(x: 180, y: 140)))
        canvas.mouseUp(with: try mouse(canvas, .leftMouseUp, at: CGPoint(x: 180, y: 140)))
        let selection = canvas.selection
        XCTAssertEqual(selection, CGRect(x: 60, y: 70, width: 120, height: 70))
        canvas.installElements(snapshot); XCTAssertEqual(canvas.selection, selection)
    }
    @MainActor func testEmptyAnnotationLayerStaysHiddenAndUndoRestoresIt() throws {
        let canvas = try canvas()
        let annotations = try XCTUnwrap(canvas.subviews.compactMap { $0 as? CaptureAnnotationView }.first)
        XCTAssertTrue(annotations.isHidden)
        canvas.restore(window); canvas.selectTool(.rectangle)
        canvas.mouseDown(with: try mouse(canvas, .leftMouseDown, at: CGPoint(x: 70, y: 80)))
        canvas.mouseDragged(with: try mouse(canvas, .leftMouseDragged, at: CGPoint(x: 150, y: 150)))
        canvas.mouseUp(with: try mouse(canvas, .leftMouseUp, at: CGPoint(x: 150, y: 150)))
        XCTAssertFalse(annotations.isHidden)
        for (flags, hidden) in [(NSEvent.ModifierFlags.command, true), ([.command, .shift], false)] {
            let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, characters: "z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6))
            canvas.keyDown(with: key); XCTAssertEqual(annotations.isHidden, hidden)
        }
    }
    @MainActor func testNoAXWindowCaptureCopiesPixelsButSecureInputKeepsPasteboardUntouched() throws {
        let prepared = try canvas()
        let canvas = CaptureCanvas(frame: window, image: prepared.image, windows: [window])
        var status = SecureInput.Status.noPermission
        canvas.allowed = { ScreenCapture.permitsCapture(status) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let output = ScreenshotOutput(allowed: { ScreenCapture.permitsCapture(status) }, pasteboard: pasteboard)
        canvas.onComplete = { image in
            do { try output.copyImage(image) } catch { XCTFail("Synthetic copy failed: \(error)") }
        }
        canvas.updateHover(at: CGPoint(x: 60, y: 70)); XCTAssertEqual(canvas.hoveredSelection, window)
        canvas.mouseDown(with: try mouse(canvas, .leftMouseDown, at: CGPoint(x: 60, y: 70)))
        canvas.mouseUp(with: try mouse(canvas, .leftMouseUp, at: CGPoint(x: 60, y: 70)))
        let enter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        canvas.keyDown(with: enter)
        let png = try XCTUnwrap(pasteboard.data(forType: .png))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(bitmap.pixelsWide, 800); XCTAssertEqual(bitmap.pixelsHigh, 600)
        try output.copyColor("#808080"); XCTAssertEqual(pasteboard.string(forType: .string), "#808080")
        let count = pasteboard.changeCount
        status = .secureInput
        canvas.keyDown(with: enter)
        XCTAssertThrowsError(try output.copyColor("#000000"))
        XCTAssertEqual(pasteboard.changeCount, count)
    }

}
