import AppKit
import SwiftUI
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor @Test func renderR3ReferenceAndStyleControls() throws {
    guard let path = ProcessInfo.processInfo.environment["ROARKT_SETTINGS_RENDER_DIR"] else { return }
    _ = NSApplication.shared
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    for dark in [false, true] {
        let scheme: ColorScheme = dark ? .dark : .light
        for (name, content) in [
            ("reference", AnyView(VStack(alignment: .leading, spacing: Tokens.Space.md) { ShortcutReference() })),
            ("annotation", AnyView(VStack(alignment: .leading, spacing: Tokens.Space.md) {
                ScreenshotStyleSettings(settings: .constant(ScreenshotSettings()), expandedTool: .text)
            }))
        ] {
            let view = content.padding(Tokens.Space.lg).frame(width: 480)
                .background(Tokens.palette(scheme).background).environment(\.colorScheme, scheme)
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: hosting.fittingSize), styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            window.close()
            try png.write(to: URL(fileURLWithPath: path).appendingPathComponent("r3-\(name)-\(dark ? "dark" : "light").png"))
        }
    }
}
