import AppKit
import SwiftUI
import XCTest
import RoarkTCore
@testable import RoarkTApp

@MainActor private final class PreviewRenderRunner: OperationRunner {
    func start() {}
    func stop() {}
    func cancel() {}
    func run(_ request: OperationRequest) -> AsyncStream<OperationEvent> {
        AsyncStream { sink in
            sink.yield(.completed(.init(session: request.session, templateID: "translate",
                text: "Project Alpha has completed the first round of testing.\nCheck the API response and error messages.\n\n    let total = values.count\n    return total", engine: "Synthetic preview")))
            sink.finish()
        }
    }
}
final class PreviewRenderingTests: XCTestCase {
    @MainActor func testProductionPreviewLightDarkAndNarrowStates() async throws {
        let image = try syntheticImage()
        for state in ["idle", "done", "loading", "error"] {
            let runner = PreviewRenderRunner()
            var continuation: CheckedContinuation<String, any Error>?
            let session = ScreenshotSession(image: image, origin: "合成评测图片", settings: { .defaults }, verified: { _, _ in false },
                allowed: { true }, recognize: { _ in
                    if state == "loading" { return try await withCheckedThrowingContinuation { continuation = $0 } }
                    if state == "error" { throw NSError(domain: "synthetic", code: 1) }
                    return "项目 Alpha 已完成第一轮测试。\n请检查 API response 和错误信息。\n\n    let total = values.count\n    return total"
                }, translationRunner: runner)
            if state != "idle" {
                session.runOCR()
                for _ in 0..<100 where session.ocrPhase == .running && continuation == nil { await Task.yield() }
            }
            if state == "done" {
                session.translate()
                for _ in 0..<100 where session.translation.phase != .done { await Task.yield() }
            }
            for dark in [false, true] {
                try render(session, state: state, dark: dark, width: 940)
            }
            if state == "done" { try render(session, state: "narrow", dark: false, width: 600) }
            session.close(); continuation?.resume(returning: "Cancelled synthetic text")
        }
    }
    @MainActor private func syntheticImage() throws -> CGImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 680, pixelsHigh: 180, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 680, height: 180).fill()
        ("项目 Alpha 已完成第一轮测试\n请检查 API response 和错误信息\n版本 Beta 将在明天发布" as NSString).draw(in: NSRect(x: 24, y: 24, width: 630, height: 140),
            withAttributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.black])
        return try XCTUnwrap(bitmap.cgImage)
    }
    @MainActor private func render(_ session: ScreenshotSession, state: String, dark: Bool, width: CGFloat) throws {
        let size = CGSize(width: width, height: 740)
        let root = ScreenshotPreviewContent(session: session, viewport: size).environment(\.colorScheme, dark ? .dark : .light)
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        hosting.displayIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(data.count, 5000)
        try data.write(to: URL(fileURLWithPath: "/tmp/roarkt-r2-preview-\(state)-\(dark ? "dark" : "light").png"))
    }
}
