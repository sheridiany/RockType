import SwiftUI

/// SPEC-006 UI-0.2 tokens.css is authoritative for shared design values.
/// Surface dimensions follow SPEC-002; no system capabilities belong here.
enum Tokens {
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }
    enum Radius {
        static let window: CGFloat = 12
        static let card: CGFloat = 10
        static let bubble: CGFloat = 16
        static let control: CGFloat = 7
    }
    enum Size {
        static let control: CGFloat = 28
        static let field: CGFloat = 26
        static let row: CGFloat = 36
        static let compact: CGFloat = 24
        static let icon: CGFloat = 16
        static let compactIcon: CGFloat = 14
        static let stroke: CGFloat = 1
        static let hairline: CGFloat = 0.5
        static let focusRing: CGFloat = 3
        static let menuWidth: CGFloat = 320
        static let resultWidth: CGFloat = 420
        static let resultMinHeight: CGFloat = 160
        static let resultMaxHeight: CGFloat = 480
        static let settingsWidth: CGFloat = 760
        static let settingsHeight: CGFloat = 540
        // Gallery reuses the settings viewport; sidebar derives from the spacing grid.
        static let gallerySidebar: CGFloat = Space.xxl * 8
        static let renderScale: CGFloat = 2
    }
    enum Typography {
        static let caption: CGFloat = 11
        static let meta: CGFloat = 12
        static let body: CGFloat = 13
        static let read: CGFloat = 14
        static let input: CGFloat = 17
        static let display: CGFloat = 28
        static let bodyLineHeight: CGFloat = 1.4
        static let readLineHeight: CGFloat = 1.65
        static let readingSpacing = read * (readLineHeight - 1)
        static func font(_ size: CGFloat = body, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight)
        }
    }
    enum Motion {
        static let appear = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.14)
        static let hover = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.12)
        static let disappear = Animation.linear(duration: 0.08)
        static let blinkDuration: TimeInterval = 1
        static let initialScale: CGFloat = 0.985
    }
    struct Palette {
        let dark: Bool
        private func hex(_ light: UInt32, _ dark: UInt32) -> Color {
            let value = self.dark ? dark : light
            return Color(.sRGB, red: Double((value >> 16) & 255) / 255,
                         green: Double((value >> 8) & 255) / 255,
                         blue: Double(value & 255) / 255, opacity: 1)
        }
        private func ink(_ light: Double, _ dark: Double) -> Color {
            (self.dark ? Color.white : Color.black).opacity(self.dark ? dark : light)
        }
        var background: Color { hex(0xf2f2f5, 0x1b1c20) }
        var window: Color { background.opacity(dark ? 0.90 : 0.93) }
        var card: Color { hex(0xffffff, 0x25262c) }
        var cardSecondary: Color { hex(0xf8f8fa, 0x212227) }
        var canvas: Color { hex(0xfcfcfd, 0x202126) }
        var bubble: Color { hex(0xf1f2f4, 0x2c2d33) }
        var askBubble: Color { hex(0xdcecff, 0x26344d) }
        var pill: Color { hex(0xffffff, 0x2e2f36) }
        var pillHover: Color { hex(0xf4f4f7, 0x383942) }
        var pillLine: Color { ink(0.12, 0.11) }
        var line: Color { ink(0.07, 0.07) }
        var lineSecondary: Color { ink(0.06, 0.06) }
        var hover: Color { ink(0.04, 0.05) }
        var selected: Color { hex(0xecebfb, 0x33345a) }
        var foreground: Color { hex(0x1c1c21, 0xededf1) }
        var secondary: Color { hex(0x4b4b53, 0xb9b9c1) }
        var tertiary: Color { hex(0x85858d, 0x9c9ca6) }
        var faint: Color { hex(0x9a9aa3, 0x7c7c87) }
        var accent: Color { hex(0x4f46e5, 0xa5b4fc) }
        var accentHover: Color { hex(0x4338ca, 0xb8c3fd) }
        var accentSoft: Color { hex(0xeeedfd, 0x2b2c47) }
        var onAccent: Color { hex(0xffffff, 0x14142a) }
        var ok: Color { hex(0x189a58, 0x6fd99b) }
        var okSoft: Color { hex(0xe4f6ec, 0x1e3a2b) }
        var warn: Color { hex(0xb45309, 0xf2b544) }
        var warnSoft: Color { hex(0xfbf0df, 0x3f3220) }
        var danger: Color { hex(0xd64545, 0xf28b82) }
        var dangerSoft: Color { hex(0xfbe9e9, 0x45272a) }
        var segmentTrack: Color { dark ? Color.white.opacity(0.045) : hex(0xebebef, 0xebebef) }
        var segmentThumb: Color { dark ? Color.white.opacity(0.1) : .white }
        var focus: Color { accent.opacity(dark ? 0.30 : 0.22) }
        var windowShadow: Color { hex(0x14161e, 0x000000).opacity(dark ? 0.55 : 0.16) }
        var windowShadowSecondary: Color { hex(0x14161e, 0x000000).opacity(dark ? 0.30 : 0.06) }
    }
    enum Shadow {
        static let windowRadius: CGFloat = 44
        static let windowY: CGFloat = 16
        static let secondaryRadius: CGFloat = 8
        static let secondaryY: CGFloat = 2
    }
    static func palette(_ scheme: ColorScheme) -> Palette { Palette(dark: scheme == .dark) }
}

struct DesignSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let colors = Tokens.palette(scheme)
        content
            .font(Tokens.Typography.font())
            .foregroundStyle(colors.foreground)
            .tint(colors.accent)
            .background(colors.canvas, in: RoundedRectangle(cornerRadius: Tokens.Radius.window))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.window)
                .stroke(colors.line, lineWidth: Tokens.Size.hairline))
    }
}
