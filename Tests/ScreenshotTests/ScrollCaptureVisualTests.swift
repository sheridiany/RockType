import AppKit
import SwiftUI
import XCTest
@testable import RoarkTApp

@MainActor private final class ScrollVisualSource: ScrollFrameSource {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
    func next() async throws -> CGImage { image }
    func stop() {}
}
final class ScrollCaptureVisualTests: XCTestCase, @unchecked Sendable {
    @MainActor func testSyntheticHUDLightAndDark() async throws {
        guard let path = ProcessInfo.processInfo.environment["ROARKT_SCROLL_ARTIFACT_DIR"] else { throw XCTSkip("Opt-in synthetic UI artifacts") }
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 1200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.97, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 400, height: 1200))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for i in 0..<8 {
            let y = 1060 - i * 140
            context.setFillColor(CGColor(red: 0.86, green: 0.91, blue: 0.98, alpha: 1)); context.fill(CGRect(x: 24, y: y, width: 352, height: 110))
            ("Synthetic section \(i + 1)" as NSString).draw(at: CGPoint(x: 38, y: y + 65), withAttributes: [.font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor.black])
            ("Capture · scroll · preview" as NSString).draw(at: CGPoint(x: 38, y: y + 25), withAttributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.darkGray])
        }
        NSGraphicsContext.restoreGraphicsState()
        let source = ScrollVisualSource(try XCTUnwrap(context.makeImage()))
        let controller = ScrollCaptureController(allowed: { true }, prepare: { source }, interval: .seconds(60))
        controller.start(); defer { controller.cancel() }
        for _ in 0..<200 { if controller.canFinish { break }; try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(controller.canFinish)
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let host = NSHostingView(rootView: ScrollCaptureView(controller: controller))
            host.frame = CGRect(origin: .zero, size: ScrollCaptureView.size)
            host.appearance = NSAppearance(named: appearance)
            let window = NSPanel(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: path).appendingPathComponent("r4-scroll-\(name).png"))
            XCTAssertGreaterThan(bitmap.pixelsHigh, 400)
            window.contentView = nil; window.close()
        }
    }
}
