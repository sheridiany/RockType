#if DEBUG
import AppKit
import Foundation
import Testing
@testable import RoarkTApp

/// Exercises the same renderer as the debug CLI without launching App/main or production listeners.
@MainActor @Test func developmentGalleryRendererExportsCatalog() throws {
    guard let path = ProcessInfo.processInfo.environment["ROARKT_GALLERY_RENDER_DIR"] else { return }
    _ = NSApplication.shared
    let count = try GalleryRenderer.render(to: URL(fileURLWithPath: path, isDirectory: true))
    #expect(count == GalleryCatalog.entries.count * GalleryTheme.allCases.count)
}
#endif
