import AppKit
import Testing
@testable import RoarkTApp

@Test @MainActor func recordingClockInkIsVerticallyCentered() throws {
    _ = NSApplication.shared
    let hud = RoarkTVoiceHUD()
    let panel = try #require(Mirror(reflecting: hud).children.first { $0.label == "panel" }?.value as? NSPanel)
    let view = try #require(panel.contentView)
    for elapsed: TimeInterval in [0, 8, 59, 60, 599] {
        hud.render(.recording)
        hud.updateRecording(elapsed: elapsed, decibels: -20)
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        var top = bitmap.pixelsHigh
        var bottom = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in Int(107 * scale)..<Int(149 * scale) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.6 {
                    top = min(top, y)
                    bottom = max(bottom, y)
                }
            }
        }
        #expect(bottom >= top, "Clock must actually render")
        let inkCenter = CGFloat(top + bottom) / 2
        let panelCenter = CGFloat(bitmap.pixelsHigh - 1) / 2
        #expect(abs(inkCenter - panelCenter) <= 1, "Clock ink must align with waveform center, elapsed: \(elapsed)")
    }
}
