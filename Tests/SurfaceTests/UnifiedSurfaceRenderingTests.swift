import AppKit
import SwiftUI
import Testing
@testable import RoarkTApp

@Suite(.serialized) @MainActor struct UnifiedSurfaceRenderingTests {
    @Test func renderUnifiedSurfaces() throws {
        guard let path = ProcessInfo.processInfo.environment["ROARKT_SURFACE_RENDER_DIR"] else { return }
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for entry in GalleryCatalog.entries where entry.surface != "settings" {
            for theme in GalleryTheme.allCases {
                let renderer = ImageRenderer(content: GalleryPreview(entry: entry, theme: theme, reduceMotion: true).fixedSize())
                renderer.scale = 2
                let image = try #require(renderer.cgImage)
                let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("\(entry.id)-\(theme.rawValue).png"))
            }
        }
    }
}

extension UnifiedSurfaceRenderingTests {
    @Test func renderProductionMenuPanel() throws {
        guard let path = ProcessInfo.processInfo.environment["ROARKT_SURFACE_RENDER_DIR"] else { return }
        _ = NSApplication.shared
        let clock = MenuBarClock()
        clock.refresh(at: Date(timeIntervalSince1970: 1_728_662_400))
        clock.stop()
        for dark in [false, true] {
            let view = ShellMenuBarPanel(clock: clock, showClock: true,
                aiStatus: "AI 已配置 · 文字、流式与图片能力待验证", showSettings: {}, quit: {})
                .environment(\.colorScheme, dark ? .dark : .light)
                .frame(width: Tokens.Size.menuWidth)
            let hosting = NSHostingView(rootView: view)
            let size = hosting.fittingSize
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.04))
            hosting.displayIfNeeded()
            let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            window.close()
            try png.write(to: URL(fileURLWithPath: path).appendingPathComponent("live-menu-\(dark ? "dark" : "light").png"))
        }
    }
}
