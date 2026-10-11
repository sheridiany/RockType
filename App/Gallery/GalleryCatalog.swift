import SwiftUI

/// One entry per surface/state. Both the window and PNG renderer consume this catalog.
struct GalleryEntry: Identifiable {
    let surface: String
    let state: String
    let title: String
    let makeView: @MainActor () -> AnyView
    var id: String { "\(surface)-\(state)" }
}

@MainActor
enum GalleryCatalog {
    // U3 (surfaces 1–5) and U4 register independent blocks.
    static let entries: [GalleryEntry] = PrimarySurfaceEntries.entries
        + InputVoiceGallery.entries
        + SettingsGallery.entries
}

enum GalleryTheme: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }
    var title: String { self == .light ? "浅色" : "深色" }
    var colorScheme: ColorScheme { self == .light ? .light : .dark }
}

/// Export uses the same environment and content as the interactive preview.
struct GalleryPreview: View {
    let entry: GalleryEntry
    let theme: GalleryTheme
    let reduceMotion: Bool
    var body: some View {
        entry.makeView()
            .environment(\.colorScheme, theme.colorScheme)
            .environment(\.designReduceMotion, reduceMotion)
    }
}
