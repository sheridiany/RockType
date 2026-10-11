import AppKit
import SwiftUI
import RoarkTCore
import XCTest
@testable import RoarkTApp

final class AnnotationStyleTests: XCTestCase {
    func testExistingSettingsDecodeAndIndependentStylesRoundTrip() throws {
        let old = Data(#"{"format":"png","ocrLanguages":["zh-Hans","en-US"]}"#.utf8)
        var settings = try JSONDecoder().decode(ScreenshotSettings.self, from: old)
        XCTAssertNil(settings.annotationStyles)
        XCTAssertEqual(ScreenshotTool.rectangle.style(from: [:]).width, 5)
        XCTAssertEqual(ScreenshotTool.arrow.style(from: [:]).width, 4)
        XCTAssertEqual(ScreenshotTool.text.style(from: [:]).width, 17)
        XCTAssertEqual(ScreenshotTool.rectangle.style(from: [:]).colorHex, "D84A2F")
        settings.annotationStyles = ["arrow": .init(colorHex: "388BEB", width: 9)]
        let decoded = try JSONDecoder().decode(ScreenshotSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(ScreenshotTool.arrow.style(from: decoded.annotationStyles!).width, 9)
        XCTAssertEqual(ScreenshotTool.rectangle.style(from: decoded.annotationStyles!).width, 5)
    }
    func testInvalidStyleValuesCannotReachRendererOrSlider() {
        let invalid: [String: ScreenshotAnnotationStyle] = ["arrow": .init(colorHex: "invalid", width: .infinity), "text": .init(width: -20)]
        XCTAssertEqual(ScreenshotTool.arrow.style(from: invalid).width, 4)
        XCTAssertEqual(ScreenshotTool.arrow.style(from: invalid).colorHex, "D84A2F")
        XCTAssertEqual(ScreenshotTool.text.style(from: invalid).width, 8)
    }
    @MainActor func testToolbarStyleChangeIsRememberedOnlyForThatTool() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let canvas = CaptureCanvas(frame: CGRect(x: 0, y: 0, width: 800, height: 600), image: try XCTUnwrap(context.makeImage()))
        canvas.restore(CGRect(x: 20, y: 20, width: 500, height: 300))
        var changes: [ScreenshotTool] = []
        canvas.onStyleChange = { tool, _ in changes.append(tool) }
        canvas.selectTool(.arrow)
        let toolbar = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSHostingView<CaptureToolbar> }.first)
        toolbar.rootView.changeStyle(.init(colorHex: "388BEB", width: 9))
        canvas.selectTool(.rectangle); XCTAssertEqual(toolbar.rootView.style.width, 5)
        canvas.selectTool(.arrow)
        XCTAssertEqual(toolbar.rootView.style, .init(colorHex: "388BEB", width: 9))
        XCTAssertEqual(changes, [.arrow])
        // Optional artifacts contain only controls and synthetic preferences, never screen captures.
        if let directory = ProcessInfo.processInfo.environment["ROARKT_SHOT_ARTIFACTS"] {
            for scheme in [ColorScheme.light, .dark] {
                let host = NSHostingView(rootView: toolbar.rootView.environment(\.colorScheme, scheme))
                host.frame = CGRect(x: 0, y: 0, width: 660, height: 94)
                let panel = NSPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.ignoresMouseEvents = true
                panel.setFrameOrigin(CGPoint(x: (NSScreen.screens.map { $0.frame.maxX }.max() ?? 0) + 100, y: 0))
                panel.contentView = host; panel.orderFrontRegardless()
                defer { panel.orderOut(nil); panel.contentView = nil; panel.close() }
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
                host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("toolbar-\(scheme == .light ? "light" : "dark").png"))
            }
        }
    }
}
