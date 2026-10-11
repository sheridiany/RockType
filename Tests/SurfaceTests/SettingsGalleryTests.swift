import AppKit
import SwiftUI
import Testing
@testable import RoarkTApp

@Suite(.serialized) @MainActor struct SettingsGalleryTests {
    @Test func settingsCatalogCoversEverySection() {
        #expect(Set(SettingsFixtures.all.map(\.section)) == Set(SettingsSection.allCases))
        #expect(Set(SettingsGallery.entries.map(\.id)).count == SettingsGallery.entries.count)
    }

    @Test func renderSettingsOffscreen() throws {
        guard let path = ProcessInfo.processInfo.environment["ROARKT_SETTINGS_RENDER_DIR"] else { return }
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for entry in SettingsGallery.entries {
            for theme in GalleryTheme.allCases {
                let renderer = ImageRenderer(content: GalleryPreview(entry: entry, theme: theme, reduceMotion: true).fixedSize())
                renderer.scale = 2
                let image = try #require(renderer.cgImage)
                let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("\(entry.id)-\(theme.rawValue).png"))
                #expect(image.width > 0 && image.height > 0)
            }
        }
    }
}

@Suite(.serialized) @MainActor struct LiveSettingsRenderingTests {
    @Test func renderProductionSettingsOffscreen() throws {
        guard let path = ProcessInfo.processInfo.environment["ROARKT_SETTINGS_RENDER_DIR"] else { return }
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let connection = ShellConnectionModel()
        connection.keyExists = { _ in false }
        connection.readKey = { _ in nil }
        let permissions = PermissionCenter(read: { _ in .notGranted }, request: { _ in
            Issue.record("Rendering must never request a permission")
        }, open: { _ in Issue.record("Rendering must never open System Settings"); return false })
        let hotkeys = HotkeyCenter(read: { .init() }, write: { _ in }, showSettings: {},
                                  allowed: { false }, trusted: { false })
        let sections = ShellSettingsSections(permissions: permissions, hotkeys: hotkeys)
        for section in SettingsSection.allCases {
            for dark in [false, true] {
              for height in [540, 1000] {
                let size = CGSize(width: 760, height: height)
                let view = ShellSettingsView(settings: .constant(.defaults), login: LoginItemController(),
                    connection: connection, sections: sections, persistenceMessage: "修改自动保存 · 离屏合成预览",
                    exportDiagnostics: {}, section: .constant(section))
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .frame(width: size.width, height: size.height)
                let hosting = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = hosting
                hosting.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.04))
                hosting.layoutSubtreeIfNeeded()
                hosting.displayIfNeeded()
                let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                window.close()
                try png.write(to: directory.appendingPathComponent("live-\(section.rawValue)-\(dark ? "dark" : "light")-\(height).png"))
            }
        }
        }
        connection.cancel()
    }
}
