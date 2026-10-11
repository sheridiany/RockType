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
                if sample.value.isVisible {
                    return AnyView(SelectionToolbarView(model: sample.value).id(sample.id))
                }
                // Gallery documentation, deliberately outside SelectionToolbarView.
                return AnyView(VStack(alignment: .leading, spacing: Tokens.Space.md) {
                    Chip(text: "Gallery 说明 · FR-E8")
                    Text("此状态不渲染任何界面")
                        .font(Tokens.Typography.font(Tokens.Typography.read, weight: .medium))
                    Text("安全输入时，划词工具栏返回空视图，不显示提示条，也不读取或处理内容。")
                }.padding(Tokens.Space.lg).frame(width: Tokens.Size.resultWidth).modifier(DesignSurface()))
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
