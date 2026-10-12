import AppKit
import SwiftUI
import QuartzCore
import XCTest
@testable import RoarkTApp

@MainActor private final class EraserTestRoot: NSView { override var isFlipped: Bool { true } }

final class E1EraserVisualTests: XCTestCase {
    private let size = CGSize(width: 640, height: 440)
    private var output: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/e1")
    }
    @MainActor private func bitmap(_ draw: (CGContext) -> Void) throws -> CGImage {
        let c = try XCTUnwrap(CGContext(data: nil, width: Int(size.width) * 2, height: Int(size.height) * 2,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        c.translateBy(x: 0, y: CGFloat(c.height)); c.scaleBy(x: 2, y: -2)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }
        draw(c); return try XCTUnwrap(c.makeImage())
    }
    private func save(_ image: CGImage, _ name: String) throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: output.appendingPathComponent(name + ".png"))
    }
    private func draw(_ image: CGImage, in c: CGContext) {
        c.saveGState(); c.translateBy(x: 0, y: size.height); c.scaleBy(x: 1, y: -1)
        c.draw(image, in: CGRect(origin: .zero, size: size)); c.restoreGState()
    }
    @MainActor private func background(dark: Bool) throws -> CGImage {
        try bitmap { c in
            c.setFillColor(NSColor(white: dark ? 0.12 : 0.98, alpha: 1).cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            c.setStrokeColor(NSColor(white: dark ? 0.2 : 0.91, alpha: 1).cgColor); c.setLineWidth(0.5)
            for x in stride(from: 24, to: 640, by: 24) { c.move(to: CGPoint(x: x, y: 60)); c.addLine(to: CGPoint(x: x, y: 420)) }
            for y in stride(from: 60, to: 440, by: 24) { c.move(to: CGPoint(x: 24, y: y)); c.addLine(to: CGPoint(x: 616, y: y)) }
            c.strokePath()
            ("橡皮擦 · 连续擦除" as NSString).draw(at: CGPoint(x: 32, y: 22), withAttributes: [
                .font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: dark ? NSColor.white : NSColor.black])
        }
    }
    private var examples: [ScreenshotAnnotation] {
        [ScreenshotAnnotation(tool: .rectangle, points: [CGPoint(x: 64, y: 90), CGPoint(x: 244, y: 190)], width: 4),
         ScreenshotAnnotation(tool: .arrow, points: [CGPoint(x: 350, y: 110), CGPoint(x: 510, y: 180)], color: .systemBlue, width: 4),
         ScreenshotAnnotation(tool: .pen, points: (0...96).map { CGPoint(x: 50 + CGFloat($0) * 5, y: 260 + sin(CGFloat($0) / 5) * 14) }, color: .systemGreen, width: 6),
         ScreenshotAnnotation(tool: .highlighter, points: [CGPoint(x: 65, y: 315), CGPoint(x: 530, y: 315)], color: .systemYellow, width: 20),
         ScreenshotAnnotation(tool: .text, points: [CGPoint(x: 300, y: 365)], text: "保留内容 · Keep", color: .systemBlue, fontSize: 21)]
    }
    @MainActor func testLightDarkHoverEraseKeyframesAndUndoFade() throws {
        for dark in [false, true] {
            let theme = dark ? "dark" : "light", image = try background(dark: dark)
            let surface = CaptureAnnotationView(frame: CGRect(origin: .zero, size: size), image: image)
            let effects = CaptureEraserEffects(frame: surface.frame, image: image)
            effects.selection = surface.bounds; effects.reducedMotion = { false }
            surface.items = examples
            func frame(_ name: String) throws {
                let annotationImage = try bitmap { _ in surface.draw(surface.bounds) }
                let feedbackImage = try bitmap { _ in effects.draw(effects.bounds) }
                let result = try bitmap { c in draw(image, in: c); draw(annotationImage, in: c); draw(feedbackImage, in: c) }
                try save(result, "\(theme)-\(name)")
            }
            effects.center = CGPoint(x: 154, y: 90); effects.frameTime = 0
            try frame("cursor-24pt")
            surface.hoveredIndices = try ScreenshotEraser.hovered(examples, sweep: .init(from: effects.center!, to: effects.center!, radius: 12))
            XCTAssertEqual(surface.hoveredIndices, [0]); try frame("hover")
            effects.diameter = 48; try frame("cursor-48pt")
            effects.diameter = 24; surface.hoveredIndices = []
            let sweep = ScreenshotEraser.Sweep(from: CGPoint(x: 154, y: 60), to: CGPoint(x: 154, y: 342), radius: 12)
            let erased = try ScreenshotEraser.erase(examples, sweeps: [sweep])
            surface.items = erased.items; effects.center = sweep.to
            effects.trail(sweep, at: 0)
            for removal in erased.removed { effects.removed([removal.annotation], sweep: removal.sweep, at: 0) }
            XCTAssertEqual(erased.removed.count, 1)
            XCTAssertEqual(erased.items.filter { $0.tool == .pen }.count, 2)
            XCTAssertEqual(erased.items.filter { $0.tool == .highlighter }.count, 2)
            for (name, time) in [("erase-000ms", 0.0), ("erase-090ms", 0.09), ("erase-180ms", 0.18), ("erase-240ms", 0.24)] {
                effects.frameTime = time; try frame(name)
            }
            effects.reducedMotion = { true }; effects.frameTime = 0.09; try frame("reduced-motion-090ms")
            effects.clear(); surface.items = examples; surface.restoredIndices = [0, 2, 3]
            effects.onFrame = { surface.restorationOpacity = $0 }; effects.restore(at: 1)
            for (name, time) in [("undo-000ms", 1.0), ("undo-075ms", 1.075), ("undo-150ms", 1.15)] {
                effects.advance(to: time); effects.frameTime = time; try frame(name)
            }
            effects.clear()
            let exported = try XCTUnwrap(ScreenshotCompositor.render(image: image, size: size,
                selection: surface.bounds, annotations: erased.items))
            try save(exported, "\(theme)-export")
        }
    }
    @MainActor func testReducedMotionKeepsOriginalBoundsAndFeedbackExpires() throws {
        let image = try background(dark: false)
        let effects = CaptureEraserEffects(frame: CGRect(origin: .zero, size: size), image: image)
        effects.selection = effects.bounds
        let sweep = ScreenshotEraser.Sweep(from: CGPoint(x: 150, y: 80), to: CGPoint(x: 150, y: 100), radius: 12)
        effects.removed([examples[0]], sweep: sweep, at: 0); effects.frameTime = 0.09
        effects.reducedMotion = { false }
        let motion = NSBitmapImageRep(cgImage: try bitmap { _ in effects.draw(effects.bounds) })
        effects.reducedMotion = { true }
        let reduced = NSBitmapImageRep(cgImage: try bitmap { _ in effects.draw(effects.bounds) })
        // At half time, normal motion has inset the rectangle's top edge; reduced motion only changes its alpha.
        XCTAssertEqual(try XCTUnwrap(motion.colorAt(x: 200, y: 180)).alphaComponent, 0)
        XCTAssertGreaterThan(try XCTUnwrap(reduced.colorAt(x: 200, y: 180)).alphaComponent, 0)
        effects.trail(sweep, at: 0); XCTAssertTrue(effects.trails.isEmpty)
        effects.frameTime = 0.24; effects.advance(to: 0.24)
        XCTAssertTrue(effects.ghosts.isEmpty)
        let cleared = try bitmap { _ in effects.draw(effects.bounds) }
        XCTAssertTrue((try XCTUnwrap(cleared.dataProvider?.data) as Data).allSatisfy { $0 == 0 })
    }
    @MainActor func testBackingLayerRemovesExpiredGhostWithoutClearingFrozenBackground() throws {
        let image = try background(dark: false), rect = CGRect(origin: .zero, size: size)
        let root = EraserTestRoot(frame: rect); root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.white.cgColor
        let effects = CaptureEraserEffects(frame: rect, image: image)
        effects.wantsLayer = true; effects.selection = rect; effects.reducedMotion = { true }; root.addSubview(effects)
        let panel = CapturePanel(captureRect: rect); panel.ignoresMouseEvents = true
        panel.setFrameOrigin(CGPoint(x: (NSScreen.screens.map { $0.frame.maxX }.max() ?? 0) + 100, y: 0))
        panel.contentView = root; panel.orderFrontRegardless()
        defer { panel.orderOut(nil); panel.contentView = nil; panel.close() }
        let start = CACurrentMediaTime()
        effects.removed([examples[0]], sweep: .init(from: CGPoint(x: 150, y: 80), to: CGPoint(x: 150, y: 100), radius: 12), at: start)
        func rendered(at time: CFTimeInterval) throws -> NSBitmapImageRep {
            effects.frameTime = time; effects.advance(to: time)
            root.layoutSubtreeIfNeeded(); root.displayIfNeeded(); effects.displayIfNeeded(); CATransaction.flush()
            return NSBitmapImageRep(cgImage: try bitmap { c in root.layer!.render(in: c) })
        }
        let visible = try XCTUnwrap(try rendered(at: start + 0.09).colorAt(x: 200, y: 180)?.usingColorSpace(.sRGB))
        XCTAssertEqual(visible.alphaComponent, 1, accuracy: 0.01)
        XCTAssertLessThan(visible.greenComponent, 0.98, "Ghost must actually be painted over the background")
        let expired = try XCTUnwrap(try rendered(at: start + 0.24).colorAt(x: 200, y: 180)?.usingColorSpace(.sRGB))
        XCTAssertEqual(expired.alphaComponent, 1, accuracy: 0.01)
        XCTAssertEqual(expired.greenComponent, 1, accuracy: 0.01, "Reused AppKit backing must not retain the old ghost")
    }
    @MainActor func testEraserToolbarInBothAppearances() throws {
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            let toolbar = CaptureToolbar(tool: .eraser, style: .init(width: 24), changeStyle: { _ in },
                canUndo: true, canRedo: false, select: { _ in }, undo: {}, redo: {}, cancel: {}, complete: {}, preview: {})
            let host = NSHostingView(rootView: toolbar); host.frame = CGRect(x: 0, y: 0, width: 660, height: 94)
            host.appearance = NSAppearance(named: appearance)
            let panel = NSPanel(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.contentView = host
            defer { panel.contentView = nil; panel.close() }
            host.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try save(try XCTUnwrap(rep.cgImage), "toolbar-\(name)")
        }
    }
}
