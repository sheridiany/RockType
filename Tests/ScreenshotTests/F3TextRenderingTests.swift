import AppKit
import SwiftUI
import XCTest
import RoarkTCore
@testable import RoarkTApp

final class F3TextRenderingTests: XCTestCase {
    private let colors = ["D84A2F", "F2B824", "40A578", "388BEB", "9B6DDF", "FFFFFF", "202124"]
    private var output: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/f3")
    }

    @MainActor private func bitmap(size: CGSize, scale: Int, draw: (CGContext) -> Void) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(size.width) * scale, height: Int(size.height) * scale,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: CGFloat(context.height))
        context.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }
        draw(context)
        return try XCTUnwrap(context.makeImage())
    }

    private func save(_ image: CGImage, _ name: String) throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: output.appendingPathComponent(name + ".png"))
    }

    @MainActor func testNativeEditorMatchesCommittedPixelsAtOneAndTwoTimesScale() throws {
        for scale in [1, 2] {
            for background in [false, true] {
                for hex in colors {
                    let annotation = ScreenshotAnnotation(tool: .text, points: [.zero],
                        text: "清晰 Clear\n第二行 123", color: ScreenshotAnnotationStyle(colorHex: hex).nsColor,
                        fontSize: 22, textMaxWidth: 172, textBackground: background)
                    var initial = annotation; initial.text = ""
                    let editor = CaptureTextView(annotation: initial, availableSize: CGSize(width: 172, height: 180))
                    editor.insertText(annotation.text, replacementRange: NSRange(location: NSNotFound, length: 0))
                    let size = CGSize(width: 180, height: 185)
                    let editing = try bitmap(size: size, scale: scale) { _ in editor.draw(editor.bounds) }
                    let committed = try bitmap(size: size, scale: scale) { _ in ScreenshotTextLayout(annotation: annotation).draw(at: .zero) }
                    let lhs = try XCTUnwrap(editing.dataProvider?.data) as Data
                    let rhs = try XCTUnwrap(committed.dataProvider?.data) as Data
                    // NSTextView clips a 1/255-alpha shadow fringe at 1x; glyph positions and visible pixels must match.
                    let maximumDifference = zip(lhs, rhs).map { abs(Int($0) - Int($1)) }.max() ?? 0
                    XCTAssertLessThanOrEqual(maximumDifference, background || scale == 2 ? 0 : 1,
                        "editor/export mismatch: \(hex), background \(background), scale \(scale)")
                    if hex == "D84A2F" {
                        try save(editing, "editing-\(background ? "background" : "plain")-\(scale)x")
                        try save(committed, "committed-\(background ? "background" : "plain")-\(scale)x")
                    }
                    let attrs = ScreenshotText.attributes(for: annotation)
                    XCTAssertNil(attrs[.strokeWidth]); XCTAssertNil(attrs[.strokeColor])
                    XCTAssertEqual(attrs[.font] as? NSFont, NSFont.systemFont(ofSize: 22, weight: .semibold))
                    if background {
                        let fill = try XCTUnwrap(annotation.color.usingColorSpace(.sRGB))
                        func linear(_ c: CGFloat) -> CGFloat { c < 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
                        let luminance = 0.2126 * linear(fill.redComponent) + 0.7152 * linear(fill.greenComponent) + 0.0722 * linear(fill.blueComponent)
                        let isWhite = ScreenshotText.foreground(for: annotation) == .white
                        XCTAssertGreaterThanOrEqual(isWhite ? 1.05 / (luminance + 0.05) : (luminance + 0.05) / 0.05, 4.5)
                    }
                }
            }
        }
    }

    @MainActor func testColorAndBackgroundComparisonSheets() throws {
        let size = CGSize(width: 900, height: 646)
        for scale in [1, 2] {
            for background in ["light", "dark", "complex"] {
                let image = try bitmap(size: size, scale: scale) { context in
                    (background == "dark" ? NSColor(srgbRed: 0.11, green: 0.12, blue: 0.14, alpha: 1) : NSColor.white).setFill()
                    context.fill(CGRect(origin: .zero, size: size))
                    if background == "complex" {
                        for row in 0..<24 {
                            for column in 0..<30 {
                                let shade = CGFloat((row * 7 + column * 11) % 10) / 12 + 0.12
                                NSColor(srgbRed: shade, green: min(1, shade + 0.12), blue: min(1, shade + 0.2), alpha: 1).setFill()
                                context.fill(CGRect(x: column * 30, y: row * 30, width: 30, height: 30))
                            }
                        }
                    }
                    NSColor(white: 0.94, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 48))
                    for (index, title) in ["原白描边", "纯色 · semibold + 淡阴影", "背景 · 自动黑白反色"].enumerated() {
                        (title as NSString).draw(at: CGPoint(x: index * 300 + 18, y: 14), withAttributes: [
                            .font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.black])
                    }
                    for (row, hex) in colors.enumerated() {
                        for column in 0..<3 {
                            let point = CGPoint(x: column * 300 + 18, y: row * 84 + 82)
                            let annotation = ScreenshotAnnotation(tool: .text, points: [point], text: "清晰文字 Clear 123",
                                color: ScreenshotAnnotationStyle(colorHex: hex).nsColor, fontSize: 22, textMaxWidth: 265,
                                textBackground: column == 2)
                            if column == 0 {
                                // Frozen pre-F3 styling, for a visible before/after comparison only.
                                (annotation.text as NSString).draw(at: point, withAttributes: [
                                    .font: NSFont.systemFont(ofSize: 22), .foregroundColor: annotation.color,
                                    .strokeColor: NSColor.white, .strokeWidth: -3])
                            } else { ScreenshotTextLayout(annotation: annotation).draw(at: point) }
                        }
                    }
                }
                try save(image, "comparison-\(background)-\(scale)x")
            }
        }
    }

    @MainActor func testTextStyleToolbarInBothAppearances() throws {
        _ = NSApplication.shared
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let toolbar = CaptureToolbar(tool: .text, style: .init(width: 22, textBackground: true), changeStyle: { _ in },
                canUndo: true, canRedo: false, select: { _ in }, undo: {}, redo: {}, cancel: {}, complete: {}, preview: {})
            let host = NSHostingView(rootView: toolbar)
            host.frame = CGRect(x: 0, y: 0, width: 660, height: 94)
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
