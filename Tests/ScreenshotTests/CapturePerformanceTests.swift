import AppKit
import QuartzCore
import Darwin
import XCTest
import RoarkTPlatform
@testable import RoarkTApp

/// Opt-in, synthetic-only benchmark. Never captures a real desktop or writes image content.
final class CapturePerformanceTests: XCTestCase {
    @MainActor private func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
    @MainActor func testSyntheticOverlayLatencyAndFootprint() throws {
        guard ProcessInfo.processInfo.environment["ROARKT_SHOT_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in synthetic benchmark") }
        _ = NSApplication.shared
        print("SYNTHETIC_ENV screens=\(NSScreen.screens.map { "\(Int($0.frame.width))x\(Int($0.frame.height))@\($0.backingScaleFactor)" }) screen_recording=\(Permissions.status(for: .screenRecording) == .granted) ax=\(Accessibility.isTrusted())")
        for (count, scale) in [(1, 1), (1, 2), (2, 2)] {
            if let scenario = ProcessInfo.processInfo.environment["ROARKT_SHOT_BENCH_SCENARIO"], scenario != "\(count)x\(scale)" { continue }
            var durations: [Double] = [], increases: [Double] = []
            var coldIncrease: Double = 0, maximumFootprint: Double = 0
            for _ in 0..<7 {
                try autoreleasepool {
                    let width = 1920, height = 1080
                    let images: [CGImage] = try (0..<count).map { index in
                        let context = try XCTUnwrap(CGContext(data: nil, width: width * scale, height: height * scale,
                            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                        context.setFillColor(CGColor(red: 0.2, green: CGFloat(index) / 3, blue: 0.8, alpha: 1))
                        context.fill(CGRect(x: 0, y: 0, width: width * scale, height: height * scale))
                        return try XCTUnwrap(context.makeImage())
                    }
                    let before = footprint(), started = CACurrentMediaTime()
                    var panels: [CapturePanel] = []
                    for index in 0..<count {
                        let rect = CGRect(x: 0, y: 0, width: width, height: height)
                        let canvas = CaptureCanvas(frame: rect, image: images[index])
                        canvas.allowed = { true }
                        let panel = CapturePanel(captureRect: rect)
                        panel.ignoresMouseEvents = true
                        panel.setFrameOrigin(CGPoint(x: (NSScreen.screens.map { $0.frame.maxX }.max() ?? 0) + 100 + CGFloat(index * width), y: 0))
                        panel.contentView = canvas; panel.orderFrontRegardless(); panel.displayIfNeeded()
                        panels.append(panel)
                    }
                    CATransaction.flush()
                    durations.append((CACurrentMediaTime() - started) * 1000)
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
                    let after = footprint()
                    increases.append(Double(after > before ? after - before : 0) / 1048576)
                    if increases.count == 1 { coldIncrease = increases[0] }
                    maximumFootprint = max(maximumFootprint, Double(after) / 1048576)
                    for panel in panels { panel.orderOut(nil); panel.contentView = nil; panel.close() }
                    CATransaction.flush()
                }
            }
            durations.sort(); increases.sort()
            print("SYNTHETIC_OVERLAY displays=\(count) source_scale=\(scale) samples=7 median_ms=\(durations[3]) max_ms=\(durations[6]) median_delta_mib=\(increases[3]) max_delta_mib=\(increases[6]) cold_delta_mib=\(coldIncrease) peak_process_mib=\(maximumFootprint)")
        }
    }
    /// Explicit opt-in only. Screen pixels stay in memory; the presentation callback immediately closes all overlays.
    @MainActor func testLiveRetinaOverlayMetrics() async throws {
        guard ProcessInfo.processInfo.environment["ROARKT_SHOT_LIVE_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in live metrics; no images saved") }
        guard Permissions.status(for: .screenRecording) == .granted else { throw XCTSkip("Screen recording permission unavailable") }
        let protection = SecureInput.status()
        guard ScreenCapture.permitsCapture(protection) else { throw XCTSkip("Capture protection: \(protection)") }
        _ = NSApplication.shared
        let enabled = ProcessInfo.processInfo.environment["ROARKT_SHOT_LIVE_AX"] == "1"
        let query = enabled ? CaptureElementQuery() : CaptureElementQuery(permitted: { false })
        let coordinator = ScreenshotCoordinator(elementQuery: query)
        coordinator.start()
        defer { coordinator.onOverlayTiming = nil; coordinator.stop() }
        try await Task.sleep(for: .milliseconds(300))
        var durations: [Double] = [], footprints: [Double] = []
        var reported = false, failed = false
        coordinator.onNotice = { _ in failed = true }
        coordinator.onOverlayTiming = { elapsed in
            durations.append(elapsed); footprints.append(Double(self.footprint()) / 1048576)
            coordinator.cancel(); reported = true
        }
        for _ in 0..<9 {
            reported = false; failed = false
            coordinator.capture()
            for _ in 0..<600 {
                if reported || failed { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            guard reported, !failed else { coordinator.cancel(); XCTFail("Live capture did not present"); return }
            try await Task.sleep(for: .milliseconds(100))
        }
        durations.sort(); footprints.sort()
        print("LIVE_OVERLAY ax=\(enabled) screens=\(NSScreen.screens.count) scales=\(NSScreen.screens.map(\.backingScaleFactor)) samples=9 median_ms=\(durations[4]) max_ms=\(durations[8]) median_process_mib=\(footprints[4]) peak_process_mib=\(footprints[8])")
        coordinator.onOverlayTiming = nil
    }

}
