import SwiftUI

/// Shared macOS visual roles. Existing property names remain stable for parallel surface work.
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
        static let candidateWidth = resultWidth
        static let modeSide = Space.xl * 2
        static let hudWidth = Space.xxl * 8
        static let hudDetailWidth = Space.xxl * 12
        static let waveformWidth = Space.xxl * 3
        static let waveformHeight = Space.lg
        static let sidebarWidth = Space.xxl * 7
        static let fieldWidth = Space.xxl * 9
        static let toggleWidth = Space.xxl + Space.sm
        static let toggleHeight = Space.xl
        static let toggleKnob = Space.lg
        static let toggleInset = stroke * 2

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
        static let recentResultRow: CGFloat = 66
        static let recentResultsMaxHeight = recentResultRow * 4
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
        static let pageTitle: CGFloat = 22
        static let display: CGFloat = 28
        static let readLineHeight: CGFloat = 1.65
        static let readingSpacing = read * (readLineHeight - 1)
        static func font(_ size: CGFloat = body, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight)
        }
    }
    enum Motion {
        static let hover = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.12)
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
        var surfaceBase: Color { hex(0xf2f2f5, 0x1b1c20) }
        var surfaceRaised: Color { hex(0xffffff, 0x25262c) }
        var textPrimary: Color { hex(0x1c1c21, 0xededf1) }
        var textSecondary: Color { hex(0x4b4b53, 0xb9b9c1) }
        var textTertiary: Color { hex(0x686872, 0xa7a7b2) }
        var borderSubtle: Color { ink(0.12, 0.14) }
        var borderControl: Color { ink(0.20, 0.23) }
        var background: Color { surfaceBase }
        var window: Color { background.opacity(dark ? 0.90 : 0.93) }
        var card: Color { surfaceRaised }
        var cardSecondary: Color { hex(0xf8f8fa, 0x212227) }
        var canvas: Color { hex(0xfcfcfd, 0x202126) }
        var bubble: Color { hex(0xf1f2f4, 0x2c2d33) }
        var askBubble: Color { hex(0xdcecff, 0x26344d) }
        var pill: Color { hex(0xffffff, 0x2e2f36) }
        var pillHover: Color { hex(0xf4f4f7, 0x383942) }
        var pillLine: Color { borderControl }
        var line: Color { borderSubtle }
        var hover: Color { ink(0.04, 0.05) }
        var selected: Color { hex(0xecebfb, 0x33345a) }
        var foreground: Color { textPrimary }
        var secondary: Color { textSecondary }
        var tertiary: Color { textTertiary }
        var accent: Color { hex(0x4f46e5, 0xa5b4fc) }
        var accentHover: Color { hex(0x4338ca, 0xb8c3fd) }
        var accentSoft: Color { hex(0xeeedfd, 0x2b2c47) }
        var onAccent: Color { hex(0xffffff, 0x14142a) }
        var ok: Color { hex(0x167442, 0x6fd99b) }
        var okSoft: Color { hex(0xe4f6ec, 0x1e3a2b) }
        var warn: Color { hex(0xa64b08, 0xf2b544) }
        var warnSoft: Color { hex(0xfbf0df, 0x3f3220) }
        var danger: Color { hex(0xb92f35, 0xf28b82) }
        var dangerSoft: Color { hex(0xfbe9e9, 0x45272a) }
        var focus: Color { accent.opacity(0.85) }
        var windowShadow: Color { hex(0x14161e, 0x000000).opacity(dark ? 0.55 : 0.16) }
        var screenshotDesktopTop: Color { hex(0xb7c8da, 0x24374d) }
        var screenshotDesktopBottom: Color { hex(0xe2d7cd, 0x534b61) }
    }
    enum Shadow {
        static let windowRadius: CGFloat = 44
        static let windowY: CGFloat = 16
        static let secondaryRadius: CGFloat = 8
        static let secondaryY: CGFloat = 2
    }
    /// Additive U3 review constants: a 1440×900 frozen desktop, shown at 2/3 size.
    enum Screenshot {
        static let screenWidth: CGFloat = 1440
        static let screenHeight: CGFloat = 900
        static let thumbnailScale: CGFloat = 2.0 / 3.0
        static let edge: CGFloat = 16
        static let selection = CGRect(x: 170, y: 240, width: 800, height: 340)
        // Bottom-edge fixture exercises toolbar placement above the selection.
        static let bottomSelection = CGRect(x: 170, y: 540, width: 800, height: 330)
        static let minimumSelection: CGFloat = 80
        static let handle: CGFloat = 8
        static let selectionStroke: CGFloat = 1.5
        static let badgeHeight: CGFloat = 28
        static let toolbarWidth: CGFloat = 580
        static let toolbarHeight: CGFloat = 48
        static let gap: CGFloat = 12
        static let ocrWidth: CGFloat = 340
        static let ocrHeight: CGFloat = 240
        static let ocrBusyHeight: CGFloat = 88
        static let menuHeight: CGFloat = 30
        static let noteWindow = CGRect(x: 100, y: 130, width: 850, height: 560)
        static let terminalWindow = CGRect(x: 380, y: 400, width: 740, height: 300)
        static let dockWidth: CGFloat = 400
        static let dockHeight: CGFloat = 64
        static let windowControls: CGFloat = 10
        static let folderWidth: CGFloat = 120
        static let folderX: CGFloat = 1260
        static let folderY: CGFloat = 110
        static let mask = Color.black.opacity(0.48)
    }
    static func palette(_ scheme: ColorScheme) -> Palette { Palette(dark: scheme == .dark) }
}

struct DesignSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        let colors = Tokens.palette(scheme)
        content
            .font(Tokens.Typography.font())
            .foregroundStyle(colors.foreground)
            .tint(colors.accent)
            .background(colors.canvas, in: RoundedRectangle(cornerRadius: Tokens.Radius.window))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.window)
                .stroke(contrast == .increased ? colors.secondary : colors.borderControl,
                        lineWidth: contrast == .increased ? Tokens.Size.stroke : Tokens.Size.hairline))
    }
}

/// Gallery may request less motion; it never overrides a system request for less motion.
private struct DesignReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var designReduceMotion: Bool {
        get { self[DesignReduceMotionKey.self] }
        set { self[DesignReduceMotionKey.self] = newValue }
    }
}
