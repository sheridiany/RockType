import AppKit
import SwiftUI
import XCTest
import RoarkTCore
@testable import RoarkTApp

final class VisualAIRenderingTests: XCTestCase {
    @MainActor func testConfirmationThinkingStreamingCompletionAndErrorInBothThemes() async throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 540, pixelsHigh: 150,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 540, height: 150).fill()
        ("Synthetic image · TEST 42" as NSString).draw(at: CGPoint(x: 24, y: 55), withAttributes: [.font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        var config = AppSettings.defaults
        config.ai.name = "Synthetic provider"; config.ai.baseURL = "https://synthetic.invalid/v1"; config.ai.visionModel = "synthetic-vision"
        for state in ["confirm", "thinking", "streaming", "done", "failed"] {
            var finish: CheckedContinuation<String, any Error>?
            let preview = ScreenshotSession(image: try XCTUnwrap(bitmap.cgImage), origin: "合成图片", settings: { config }, verified: { _, _ in true },
                allowed: { true }, sendVisual: { _, thinking, delta, _ in
                    if state == "failed" { throw AIClientError.timeout }
                    if state == "done" { return "这张合成图片显示 TEST 42。\n\n• 用于验证图片与用户编辑文字一起发送\n• 结果可复制，也可继续追问" }
                    await thinking()
                    if state == "streaming" { await delta("这张合成图片显示 TEST 42。\n正在整理可见内容…") }
                    return try await withCheckedThrowingContinuation { finish = $0 }
                })
            preview.text = "用户核对后的合成文字：TEST 42\n这是确认页实际将发送的文字。"
            preview.prepareImage(action: .summarize)
            if state != "confirm" {
                preview.confirmImage()
                for _ in 0..<100 where preview.visual.phase == .running { await Task.yield() }
            }
            for dark in [false, true] { try render(preview, state: state, dark: dark) }
            preview.close(); finish?.resume(returning: "Cancelled synthetic result")
        }
    }
    @MainActor private func render(_ preview: ScreenshotSession, state: String, dark: Bool) throws {
        let size = CGSize(width: 900, height: 760)
        let root = ScreenshotPreviewContent(session: preview, viewport: size).environment(\.colorScheme, dark ? .dark : .light)
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        hosting.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(data.count, 5000)
        try data.write(to: URL(fileURLWithPath: "/tmp/roarkt-r2b-\(state)-\(dark ? "dark" : "light").png"))
    }
}
