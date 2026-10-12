import AppKit
import QuartzCore
import XCTest
import RoarkTPlatform
@testable import RoarkTApp

final class CaptureEntryTests: XCTestCase {
    @MainActor func testCaptureDoesNotHideFloatingWindowsWhileWaitingForPixels() async {
        let window = EntryFloatingWindow(contentRect: .init(x: 0, y: 0, width: 20, height: 20),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.level = .floating
        defer { window.close() }
        let captured = expectation(description: "capture reached")
        let coordinator = ScreenshotCoordinator(captureFrames: {
            XCTAssertEqual(window.hideCount, 0, "Hiding a live window before asynchronous capture leaves a visible uncovered interval")
            captured.fulfill()
            throw ScreenCapture.Failure.unavailable
        }, allowed: { true }, elementQuery: CaptureElementQuery(permitted: { false }))
        coordinator.onNotice = { _ in }
        coordinator.start(); coordinator.capture()
        await fulfillment(of: [captured], timeout: 2)
        coordinator.stop()
    }

    @MainActor func testReadyOverlaysCoverAllDisplaysBeforeHidingAndRestoreOnCancel() async throws {
        let floating = EntryFloatingWindow(contentRect: .init(x: 0, y: 0, width: 20, height: 20),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        floating.isReleasedWhenClosed = false; floating.level = .floating
        defer { floating.close() }
        let context = try XCTUnwrap(CGContext(data: nil, width: 160, height: 100, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let farRight = (NSScreen.screens.map { $0.frame.maxX }.max() ?? 0) + 100
        let frames: [ScreenCapture.Frame] = [0, 1].map {
            .init(displayID: UInt32(900 + $0), rect: CGRect(x: farRight + CGFloat($0 * 180), y: 0, width: 160, height: 100), image: image)
        }
        let coordinator = ScreenshotCoordinator(captureFrames: { frames }, allowed: { true },
            elementQuery: CaptureElementQuery(permitted: { false }))
        defer { coordinator.stop() }
        floating.onHide = {
            let panels = NSApp.windows.filter { ($0.contentView as? CaptureCanvas)?.image === image }
            XCTAssertEqual(panels.count, 2)
            XCTAssertTrue(panels.allSatisfy { $0.isVisible && $0.contentView?.layer?.sublayers?.first?.contents != nil },
                "Every display must have its filled overlay before a live window is hidden")
        }
        let shown = expectation(description: "all overlays shown")
        coordinator.onOverlayTiming = { _ in shown.fulfill() }
        coordinator.start(); coordinator.capture()
        await fulfillment(of: [shown], timeout: 2)
        XCTAssertEqual(floating.hideCount, 1)
        floating.onHide = {}
        coordinator.cancel()
        XCTAssertEqual(floating.restoreCount, 1)
        XCTAssertFalse(NSApp.windows.contains { ($0.contentView as? CaptureCanvas)?.image === image })
    }

    @MainActor func testCancellationDuringSamplingLeavesFloatingWindowsUntouched() async {
        let window = EntryFloatingWindow(contentRect: .init(x: 0, y: 0, width: 20, height: 20),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.level = .floating
        defer { window.close() }
        var reply: CheckedContinuation<[ScreenCapture.Frame], any Error>?
        let entered = expectation(description: "sampling started")
        let coordinator = ScreenshotCoordinator(captureFrames: {
            try await withCheckedThrowingContinuation { reply = $0; entered.fulfill() }
        }, allowed: { true }, elementQuery: CaptureElementQuery(permitted: { false }))
        defer { coordinator.stop() }
        coordinator.start(); coordinator.capture()
        await fulfillment(of: [entered], timeout: 2)
        coordinator.cancel(); reply?.resume(returning: [])
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(window.hideCount, 0); XCTAssertEqual(window.restoreCount, 0)
    }

    @MainActor func testFrozenPixelsMatchScreenSnapshotAtOneAndTwoTimesScale() throws {
        for (name, rect, scale) in [
            ("origin-1x", CGRect(x: 0, y: 0, width: 192, height: 128), 1),
            ("left-2x", CGRect(x: -192, y: 240, width: 192, height: 128), 2),
            ("below-2x", CGRect(x: 480, y: -128, width: 192, height: 128), 2)
        ] {
            let width = Int(rect.width) * scale, height = Int(rect.height) * scale
            var bytes = [UInt8](repeating: 255, count: width * height * 4)
            for y in 0..<height { for x in 0..<width {
                let i = (y * width + x) * 4
                bytes[i] = UInt8((x * 17 + y * 3) % 256)
                bytes[i + 1] = UInt8((y * 13 + x * 5) % 256)
                bytes[i + 2] = UInt8((x ^ y) % 256)
            } }
            let space = CGColorSpaceCreateDeviceRGB()
            let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
            let panel = CapturePanel(captureRect: rect)
            let canvas = CaptureCanvas(frame: CGRect(origin: .zero, size: rect.size), image: image)
            panel.contentView = canvas
            defer { panel.contentView = nil; panel.close() }
            XCTAssertEqual(panel.frame, rect, "Global display origin must not be clamped to the visible frame")
            canvas.layoutSubtreeIfNeeded(); canvas.displayIfNeeded()
            let root = try XCTUnwrap(canvas.layer)
            XCTAssertTrue(root.sublayers?.first?.animationKeys()?.isEmpty ?? true)
            // Isolate only the frozen plane; darkening, labels and selection are intentionally overlays.
            for layer in root.sublayers?.dropFirst() ?? [] { layer.isHidden = true }
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
            root.render(in: context)
            let actual = Array(UnsafeBufferPointer(start: try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self), count: bytes.count))
            XCTAssertEqual(zip(bytes, actual).filter { $0 != $1 }.count, 0, "\(name): every channel must match; even a one-pixel shift must fail")
            if let directory = ProcessInfo.processInfo.environment["ROARKT_F1_ARTIFACT_DIR"] {
                let url = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                for (suffix, output) in [("source", image), ("frozen", try XCTUnwrap(context.makeImage()))] {
                    try XCTUnwrap(NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:]))
                        .write(to: url.appendingPathComponent("\(name)-\(suffix).png"))
                }
            }
        }
    }

    @MainActor func testOverlayDoesNotUseWindowServerEntranceAnimation() {
        let panel = CapturePanel(captureRect: .init(x: -320, y: 180, width: 160, height: 100))
        defer { panel.close() }
        XCTAssertEqual(panel.animationBehavior, .none)
    }
}

@MainActor private final class EntryFloatingWindow: NSPanel {
    var hideCount = 0
    var restoreCount = 0
    var onHide: () -> Void = {}
    override var isVisible: Bool { true }
    override func orderOut(_ sender: Any?) { onHide(); hideCount += 1 }
    override func orderFrontRegardless() { restoreCount += 1 }
}
