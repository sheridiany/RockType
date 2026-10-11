import AppKit
import SwiftUI
import Testing
@testable import RoarkTApp

@MainActor @Test func smallTextAndStatusColorsRemainReadableInBothThemes() throws {
    func luminance(_ color: Color) throws -> Double {
        let rgb = try #require(NSColor(color).usingColorSpace(.sRGB))
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return linear(rgb.redComponent) * 0.2126 + linear(rgb.greenComponent) * 0.7152 + linear(rgb.blueComponent) * 0.0722
    }
    for scheme in [ColorScheme.light, .dark] {
        let p = Tokens.palette(scheme)
        let pairs: [(Color, Color)] = [(p.foreground, p.canvas), (p.secondary, p.background), (p.tertiary, p.canvas),
                                       (p.ok, p.okSoft), (p.warn, p.warnSoft), (p.danger, p.dangerSoft), (p.onAccent, p.accent)]
        for (index, pair) in pairs.enumerated() {
            let (ink, background) = pair
            let a = try luminance(ink), b = try luminance(background)
            #expect((max(a, b) + 0.05) / (min(a, b) + 0.05) >= 4.5, "Theme: \(scheme), pair: \(index)")
        }
    }
}
