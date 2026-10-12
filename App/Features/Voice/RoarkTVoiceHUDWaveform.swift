import AppKit

/// Meter history stays real; only the silent baseline and busy states use ambient motion.
@MainActor final class RoarkTVoiceHUDWaveform: NSView {
    enum Mode { case preparing, recording, processing, polishing, success, noSpeech }
    private(set) var levels = Array(repeating: CGFloat.zero, count: 9)
    var mode: Mode = .preparing { didSet { needsDisplay = true } }
    var phase: Double = 0 { didSet { needsDisplay = true } }
    var reducedMotion = false { didSet { needsDisplay = true } }

    func reset() { levels = Array(repeating: 0, count: 9); needsDisplay = true }
    func append(decibels: Float) {
        let value = decibels.isFinite ? CGFloat(max(0, min(1, (decibels + 55) / 45))) : 0
        levels.removeFirst(); levels.append(value); needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let time = reducedMotion ? 0 : phase
        if mode == .success {
            NSColor.white.setStroke()
            let path = NSBezierPath(); path.lineWidth = 2; path.lineCapStyle = .round; path.lineJoinStyle = .round
            path.move(to: NSPoint(x: bounds.midX - 6, y: bounds.midY))
            path.line(to: NSPoint(x: bounds.midX - 1.5, y: bounds.midY - 4))
            path.line(to: NSPoint(x: bounds.midX + 7, y: bounds.midY + 5))
            path.stroke(); return
        }
        if mode == .processing || mode == .polishing {
            for index in 0..<3 {
                let pulse = reducedMotion ? 0 : sin(time * 7 - Double(index) * 0.85)
                NSColor.white.withAlphaComponent(0.65 + 0.35 * max(0, pulse)).setFill()
                let y = bounds.midY + max(0, pulse) * 2.5
                NSBezierPath(ovalIn: NSRect(x: bounds.midX - 11 + CGFloat(index) * 9, y: y - 2, width: 4, height: 4)).fill()
            }
            return
        }
        let silent = levels.allSatisfy { $0 < 0.015 }
        for index in 0..<9 {
            var height: CGFloat = 2.5
            var alpha = 0.9
            if mode == .recording {
                height += levels[index] * 15
                if silent { alpha = reducedMotion ? 0.65 : 0.6 + 0.15 * sin(time * 2.8) }
            } else if mode == .preparing {
                let cursor = reducedMotion ? 4 : time.truncatingRemainder(dividingBy: 1.15) / 1.15 * 13 - 2
                let pulse = exp(-pow(Double(index) - cursor, 2) / 2)
                height += 10 * pulse; alpha = 0.3 + 0.65 * pulse
            } else { alpha = 0.5 }
            NSColor.white.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: NSRect(x: bounds.midX - 29.5 + CGFloat(index) * 7,
                                             y: bounds.midY - height / 2, width: 3, height: height),
                         xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}
