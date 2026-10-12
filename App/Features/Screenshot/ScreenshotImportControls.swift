import SwiftUI
import UniformTypeIdentifiers

/// Embed in the menu-bar panel; no Dock icon or window is created. AppDelegate owns the coordinator.
struct ScreenshotImportControls: View {
    let coordinator: ScreenshotCoordinator
    var prepare: () -> Void = {}
    @State private var targeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            HStack {
                Button("截图历史") { prepare(); coordinator.showHistory() }
                Menu("贴图群组") {
                    Button("隐藏／显示全部") { prepare(); coordinator.cancel(); PinnedImageController.shared.toggleAll() }
                    Button("下一张贴图") { prepare(); coordinator.cancel(); PinnedImageController.shared.focusNext() }
                    Button("关闭全部") { prepare(); coordinator.cancel(); PinnedImageController.shared.closeGroup() }
                }
            }.buttonStyle(DesignButtonStyle(variant: .ghost))
            Button { prepare(); coordinator.openClipboardImage(recognize: true) } label: {
                ScreenshotLabel("识别剪贴板图片", systemImage: ScreenshotSymbols.clipboard)
            }.buttonStyle(DesignButtonStyle(variant: .secondary))
            HStack {
                Button("预览剪贴板图片") { prepare(); coordinator.openClipboardImage() }
                Button("批量识别…") { prepare(); coordinator.openImageFiles() }
            }.buttonStyle(DesignButtonStyle(variant: .ghost))
            ScreenshotLabel(targeted ? "松开以打开图片" : "拖入图片，识别文字或解释图片", systemImage: ScreenshotSymbols.images)
                .padding(Tokens.Space.md).frame(maxWidth: .infinity)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                .onDrop(of: [UTType.image, .fileURL], isTargeted: $targeted) { providers in
                    let accepted = coordinator.acceptDrop(providers)
                    if accepted { prepare() }
                    return accepted
                }
                .accessibilityLabel("拖入图片区域；也可使用从剪贴板打开图片按钮")
        }
    }
}
