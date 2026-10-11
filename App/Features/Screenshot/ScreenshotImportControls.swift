import SwiftUI
import UniformTypeIdentifiers

/// Embed in the menu-bar panel; no Dock icon or window is created. AppDelegate owns the coordinator.
struct ScreenshotImportControls: View {
    let coordinator: ScreenshotCoordinator
    @State private var targeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            Button("从剪贴板打开图片") { coordinator.openClipboardImage() }
                .buttonStyle(DesignButtonStyle(variant: .secondary))
            Label(targeted ? "松开以打开图片" : "拖入图片，识别文字或解释图片", systemImage: "photo.on.rectangle")
                .padding(Tokens.Space.md).frame(maxWidth: .infinity)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                .onDrop(of: [UTType.image, .fileURL], isTargeted: $targeted) { providers in
                    coordinator.acceptDrop(providers)
                }
                .accessibilityLabel("拖入图片区域；也可使用从剪贴板打开图片按钮")
        }
    }
}
