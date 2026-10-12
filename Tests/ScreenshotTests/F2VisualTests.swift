import AppKit
import SwiftUI
import QuartzCore
import XCTest
@testable import RoarkTApp

final class F2VisualTests: XCTestCase {
    @MainActor private func canvas(scale: Int, background: String) throws -> CaptureCanvas {
        let size = CGSize(width: 640, height: 380)
        let ctx = try XCTUnwrap(CGContext(data: nil, width: Int(size.width) * scale, height: Int(size.height) * scale,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        ctx.setFillColor(CGColor(gray: background == "dark" ? 0.04 : 0.96, alpha: 1)); ctx.fill(CGRect(origin: .zero, size: size))
        if background == "busy" {
            for y in stride(from: 0, to: 380, by: 20) { for x in stride(from: 0, to: 640, by: 20) {
                ctx.setFillColor(CGColor(gray: (x + y) % 40 == 0 ? 0.08 : 0.94, alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: 20, height: 20))
            } }
        }
        let canvas = CaptureCanvas(frame: CGRect(origin: .zero, size: size), image: try XCTUnwrap(ctx.makeImage()))
        canvas.selection = CGRect(x: 80.25, y: 90.25, width: 400, height: 180)
        canvas.layoutSubtreeIfNeeded()
        return canvas
    }

    @MainActor private func bitmap(_ canvas: CaptureCanvas, scale: Int) throws -> NSBitmapImageRep {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: Int(canvas.bounds.width) * scale,
            height: Int(canvas.bounds.height) * scale, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.translateBy(x: 0, y: canvas.bounds.height * CGFloat(scale)); ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        CATransaction.flush()
        try XCTUnwrap(canvas.layer).render(in: ctx)
        return NSBitmapImageRep(cgImage: try XCTUnwrap(ctx.makeImage()))
    }

    @MainActor func testSelectionContrastAndPixelAlignmentWithoutChangingCrop() throws {
        for scale in [1, 2] { for background in ["light", "dark", "busy"] {
            let view = try canvas(scale: scale, background: background)
            let original = view.selection
            let rep = try bitmap(view, scale: scale)
            let x = Int((original.minX * CGFloat(scale)).rounded())
            let y = 140 * scale
            func brightness(_ x: Int, _ y: Int) throws -> CGFloat {
                let c = try XCTUnwrap(rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                return min(c.redComponent, c.greenComponent, c.blueComponent)
            }
            // Two solid points of white, with a visible dark keyline on either side.
            // Fractional selections used to leave a partially covered/soft edge.
            for column in (x - scale)..<(x + scale) {
                XCTAssertGreaterThan(try brightness(column, y), 0.95)
            }
            XCTAssertLessThan(try brightness(x - scale - 1, y), 0.35)
            XCTAssertLessThan(try brightness(x + scale, y), 0.35)
            for handle in ScreenshotHandle.allCases {
                let point = handle.point(in: original)
                XCTAssertGreaterThan(try brightness(Int((point.x * CGFloat(scale)).rounded()),
                                                    Int((point.y * CGFloat(scale)).rounded())), 0.95)
            }
            XCTAssertEqual(view.selection, original, "Visual snapping must never round the actual crop")
        } }
    }

    @MainActor func testExportSyntheticBeforeAfterMatrix() throws {
        guard let path = ProcessInfo.processInfo.environment["ROARKT_F2_RENDER_DIR"] else { return }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for background in ["light", "dark", "busy"] { for scale in [1, 2] {
            let view = try canvas(scale: scale, background: background)
            let rep = try bitmap(view, scale: scale)
            try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                .write(to: output.appendingPathComponent("selection-\(background)@\(scale)x.png"))
        } }
        for scheme in [ColorScheme.light, .dark] { for width in [660, 420] {
            for tool in [ScreenshotTool?.none, .some(.arrow), .some(.eraser)] {
                let toolbar = CaptureToolbar(tool: tool, style: .init(), changeStyle: { _ in },
                    canUndo: tool != nil, canRedo: false, select: { _ in }, undo: {}, redo: {}, cancel: {}, complete: {}, preview: {})
                let host = NSHostingView(rootView: toolbar.environment(\.colorScheme, scheme))
                host.frame = CGRect(x: 0, y: 0, width: width, height: 94)
                let panel = NSPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false
                panel.contentView = host
                host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(
                    "toolbar-\(scheme == .light ? "light" : "dark")-\(width)-\(tool?.rawValue ?? "select").png"))
                panel.contentView = nil; panel.close()
            }
        } }
    }
}
