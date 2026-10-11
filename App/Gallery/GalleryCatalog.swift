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
    static let entries: [GalleryEntry] = [
        GalleryEntry(surface: "result", state: "streaming", title: "结果浮窗 · 流式中") {
            AnyView(ResultExampleView(model: .streaming))
        },
        GalleryEntry(surface: "result", state: "done", title: "结果浮窗 · 完成") {
            AnyView(ResultExampleView(model: .done))
        },
    ]
    // U4: independent registration block; surfaces 1–5 are maintained separately.
    + InputVoiceGallery.entries
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
