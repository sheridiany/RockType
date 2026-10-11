import AppKit

/// Recent real meter samples, not a decorative looping waveform.
@MainActor
final class RoarkTVoiceHUDWaveform: NSView {
    private(set) var levels = Array(repeating: CGFloat.zero, count: 9)

    func reset() { levels = Array(repeating: 0, count: 9); needsDisplay = true }

    func append(decibels: Float) {
        let normalized = decibels.isFinite ? CGFloat(max(0, min(1, (decibels + 55) / 45))) : 0
        levels.removeFirst()
        levels.append(normalized)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.85, green: 0.89, blue: 0.81, alpha: 1).setFill()
        for (index, level) in levels.enumerated() {
            let height = 2 + level * 16
            let rect = NSRect(x: bounds.midX - 21 + CGFloat(index) * 5, y: bounds.midY - height / 2,
                              width: 2, height: height)
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
        }
    }
}
