import AppKit
import RoarkTPlatform
import XCTest
@testable import RoarkTApp

final class CaptureCancellationTests: XCTestCase {
    @MainActor private func capture() async throws -> (ScreenshotCoordinator, [CaptureCanvas]) {
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let edge = (NSScreen.screens.map { $0.frame.maxX }.max() ?? 0) + 100
        let frames = (0..<2).map { index in
            ScreenCapture.Frame(displayID: UInt32(950 + index),
                rect: CGRect(x: edge + CGFloat(index * 660), y: 0, width: 640, height: 480), image: image)
        }
        let coordinator = ScreenshotCoordinator(captureFrames: { frames }, allowed: { true },
            elementQuery: CaptureElementQuery(permitted: { false }))
        let shown = expectation(description: "synthetic overlays ready")
        coordinator.onOverlayTiming = { _ in shown.fulfill() }
        coordinator.start(); coordinator.capture()
        await fulfillment(of: [shown], timeout: 2)
        let canvases = NSApp.windows.compactMap { $0.contentView as? CaptureCanvas }.filter { $0.image === image }
        guard canvases.count == 2 else { coordinator.stop(); XCTFail("Missing synthetic overlays"); throw CancellationError() }
        return (coordinator, canvases)
    }

    @MainActor private func mouse(_ type: NSEvent.EventType, on canvas: CaptureCanvas,
                                 at point: CGPoint = CGPoint(x: 600, y: 450)) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [],
            timestamp: 0, windowNumber: try XCTUnwrap(canvas.window).windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
    }

    @MainActor func testRightClickCancelsBeforeAndAfterSelectionAcrossAllOverlays() async throws {
        for selected in [false, true] {
            let (coordinator, canvases) = try await capture()
            defer { coordinator.stop() }
            let panels = canvases.compactMap(\.window)
            if selected { canvases[0].restore(CGRect(x: 20, y: 20, width: 500, height: 300)) }
            var outputs = 0
            canvases.forEach { $0.onComplete = { _ in outputs += 1 } }
            let right = try mouse(.rightMouseDown, on: canvases[0])
            XCTAssertNil(coordinator.routeCanvasEvent(right))
            XCTAssertTrue(panels.allSatisfy { !$0.isVisible && $0.contentView == nil })
            XCTAssertEqual(outputs, 0)
            XCTAssertTrue(coordinator.history.entries.isEmpty)
        }
    }

    @MainActor func testRightClickPreservesMarkedTextEvenOnAnotherDisplay() async throws {
        let (coordinator, canvases) = try await capture()
        defer { coordinator.stop() }
        let canvas = canvases[0]
        canvas.restore(CGRect(x: 20, y: 20, width: 500, height: 300)); canvas.selectTool(.text)
        let click = try mouse(.leftMouseDown, on: canvas, at: CGPoint(x: 45, y: 45))
        canvas.mouseDown(with: click); canvas.mouseUp(with: click)
        let editor = try XCTUnwrap(canvas.subviews.compactMap { $0 as? CaptureTextView }.first)
        editor.setMarkedText("合成输入", selectedRange: NSRange(location: 4, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        for target in canvases {
            XCTAssertNotNil(coordinator.routeCanvasEvent(try mouse(.rightMouseDown, on: target)))
            XCTAssertTrue(canvas.isEditingText)
            XCTAssertTrue(editor.hasMarkedText())
            XCTAssertEqual(editor.string, "合成输入")
            XCTAssertTrue(canvas.annotations.isEmpty)
            XCTAssertTrue(canvases.allSatisfy { $0.window?.isVisible == true })
        }
        // Ordinary left clicks retain the existing commit behavior.
        XCTAssertNotNil(coordinator.routeCanvasEvent(try mouse(.leftMouseDown, on: canvases[1])))
        XCTAssertFalse(canvas.isEditingText)
        XCTAssertEqual(canvas.annotations.count, 1)
    }

    @MainActor func testRightClickInOtherWindowDoesNotCancelCapture() async throws {
        let (coordinator, canvases) = try await capture()
        defer { coordinator.stop() }
        let panel = NSPanel(contentRect: CGRect(x: -1000, y: -1000, width: 20, height: 20),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = CaptureCanvas(frame: panel.contentLayoutRect, image: canvases[0].image)
        defer { panel.contentView = nil; panel.close() }
        let right = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        XCTAssertNotNil(coordinator.routeCanvasEvent(right))
        XCTAssertTrue(canvases.allSatisfy { $0.window?.isVisible == true })
    }
}
