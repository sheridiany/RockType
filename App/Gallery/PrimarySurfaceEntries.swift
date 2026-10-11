import SwiftUI

@MainActor
enum PrimarySurfaceEntries {
    private static let rendering = CommandLine.arguments.contains("--render-gallery")
    static let entries: [GalleryEntry] =
        MenuBarPanelModel.samples.map { sample in
            GalleryEntry(surface: "menu", state: sample.id.lowercased(), title: "菜单栏 · " + sample.title) {
                AnyView(MenuBarPanelView(model: sample.value).id(sample.id))
            }
        } + SelectionToolbarModel.samples.map { sample in
            GalleryEntry(surface: "selection", state: sample.id.lowercased(), title: "划词工具栏 · " + sample.title) {
                AnyView(SelectionToolbarView(model: sample.value).id(sample.id))
            }
        } + ResultWindowModel.samples.map { sample in
            GalleryEntry(surface: "result", state: sample.id.lowercased(), title: "结果浮窗 · " + sample.title) {
                AnyView(ResultWindowView(model: sample.value, rendering: rendering).id(sample.id))
            }
        } + ScreenshotEditorModel.samples.map { sample in
            GalleryEntry(surface: "screenshot", state: sample.id.lowercased(), title: "截图编辑器 · " + sample.title) {
                AnyView(ScreenshotEditorView(model: sample.value, rendering: rendering).id(sample.id))
            }
        } + ImagePreviewModel.samples.map { sample in
            GalleryEntry(surface: "image", state: sample.id.lowercased(), title: "图片预览 · " + sample.title) {
                AnyView(ImagePreviewView(model: sample.value, rendering: rendering).id(sample.id))
            }
        }
}
