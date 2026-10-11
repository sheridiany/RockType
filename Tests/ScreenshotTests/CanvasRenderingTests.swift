import AppKit
import QuartzCore
import XCTest
@testable import RoarkTApp

final class CanvasRenderingTests: XCTestCase {
    @MainActor func testOrderedPanelRendersFrozenImageMaskAndSelection() throws {
        try assertRenderedCanvas(rebuildBacking: false)
    }
    @MainActor func testBackingLayerRecreationPreservesVisibleCanvas() throws {
        try assertRenderedCanvas(rebuildBacking: true)
    }
    @MainActor func testFrozenImageKeepsTopLeftOrientation() throws {
        try assertRenderedCanvas(rebuildBacking: false, orientationStripe: true)
    }
    @MainActor private func assertRenderedCanvas(rebuildBacking: Bool, orientationStripe: Bool = false) throws {
        let bounds = CGRect(x: 0, y: 0, width: 240, height: 180)
        let source = try XCTUnwrap(CGContext(data: nil, width: 240, height: 180, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        source.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        source.fill(bounds)
        if orientationStripe {
            source.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            source.fill(CGRect(x: 220, y: 90, width: 20, height: 90))
            source.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            source.fill(CGRect(x: 220, y: 0, width: 20, height: 90))
        }
        let canvas = CaptureCanvas(frame: bounds, image: try XCTUnwrap(source.makeImage()))
        // Exercise real AppKit window attachment/display without activating the app or taking input.
        let panel = CapturePanel(captureRect: bounds)
        panel.ignoresMouseEvents = true
        panel.setFrameOrigin(CGPoint(x: (NSScreen.screens.map { $0.frame.maxX }.max() ?? 0) + 100, y: 0))
        defer { panel.orderOut(nil); panel.contentView = nil; panel.close() }
        panel.contentView = canvas
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        if rebuildBacking {
            panel.orderOut(nil)
            panel.contentView = nil
            // Explicitly simulate AppKit replacing its backing root. Do not change any canvas
            // content, selection, or subviews: the same image must survive reattachment.
            canvas.wantsLayer = false
            canvas.layer = nil
            canvas.wantsLayer = true
            panel.contentView = canvas
            panel.orderFrontRegardless()
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.alphaValue, 1)
        XCTAssertTrue(panel.isOpaque)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        func render() throws -> NSBitmapImageRep {
            panel.displayIfNeeded()
            canvas.layoutSubtreeIfNeeded(); canvas.displayIfNeeded()
            CATransaction.flush()
            let context = try XCTUnwrap(CGContext(data: nil, width: 240, height: 180, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            try XCTUnwrap(canvas.layer).render(in: context)
            return NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        }
        func color(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) throws -> NSColor {
            try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        }
        let initial = try render()
        let masked = try color(initial, 180, 90)
        XCTAssertEqual(masked.alphaComponent, 1, accuracy: 0.02)
        XCTAssertEqual(masked.redComponent, 0, accuracy: 0.03, "Frozen image must remain visible below the mask")
        XCTAssertEqual(masked.greenComponent, 0.52, accuracy: 0.03)
        XCTAssertEqual(masked.blueComponent, 0, accuracy: 0.03)

        // The hint label must also contain visible text, not merely a retained CATextLayer.
        var whitePixels = 0
        for y in 8..<28 {
            for x in 8..<224 {
                let pixel = try color(initial, x, y)
                if min(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) > 0.8 { whitePixels += 1 }
            }
        }
        XCTAssertGreaterThan(whitePixels, 10, "Shortcut label must be painted")

        canvas.selection = CGRect(x: 40, y: 40, width: 100, height: 60)
        let selected = try render()
        let inside = try color(selected, 90, 60)
        XCTAssertEqual(inside.redComponent, 0, accuracy: 0.03)
        XCTAssertEqual(inside.greenComponent, 1, accuracy: 0.03)
        XCTAssertEqual(inside.blueComponent, 0, accuracy: 0.03)
        let outside = try color(selected, 180, 90)
        XCTAssertEqual(outside.redComponent, masked.redComponent, accuracy: 0.03)
        XCTAssertEqual(outside.greenComponent, masked.greenComponent, accuracy: 0.03)
        XCTAssertEqual(outside.alphaComponent, 1, accuracy: 0.02)
        let mirrored = try color(selected, 90, 120)
        XCTAssertEqual(mirrored.greenComponent, 0.52, accuracy: 0.03, "Selection must use top-left coordinates")
        if orientationStripe {
            let top = try color(selected, 230, 60)
            let bottom = try color(selected, 230, 120)
            XCTAssertEqual(top.redComponent, 0.52, accuracy: 0.03)
            XCTAssertEqual(top.blueComponent, 0, accuracy: 0.03)
            XCTAssertEqual(bottom.blueComponent, 0.52, accuracy: 0.03)
            XCTAssertEqual(bottom.redComponent, 0, accuracy: 0.03)
        }
        let border = try color(selected, 40, 60)
        XCTAssertGreaterThan(abs(border.redComponent - inside.redComponent)
            + abs(border.greenComponent - inside.greenComponent)
            + abs(border.blueComponent - inside.blueComponent), 0.2, "Selection border must be painted")
    }
}
