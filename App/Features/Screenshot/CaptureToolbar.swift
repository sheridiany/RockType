import SwiftUI

struct CaptureToolbar: View {
    let tool: ScreenshotEditorModel.Tool?
    let canUndo: Bool
    let canRedo: Bool
    let select: (ScreenshotEditorModel.Tool?) -> Void
    let undo: () -> Void
    let redo: () -> Void
    let cancel: () -> Void
    let complete: () -> Void
    let preview: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Tokens.palette(scheme)
        HStack(spacing: Tokens.Space.xs) {
            Button { select(nil) } label: { Image(systemName: "cursorarrow") }.help("调整选区 · R 恢复上次选区")
            ForEach(ScreenshotEditorModel.Tool.allCases, id: \.self) { item in
                Button { select(item) } label: { Image(systemName: item.symbol) }
                    .background(tool == item ? p.selected : .clear, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
                    .help(item.title).accessibilityLabel(item.title)
            }
            Divider().frame(height: Tokens.Size.compact)
            Button(action: undo) { Image(systemName: "arrow.uturn.backward") }.disabled(!canUndo).help("撤销 ⌘Z")
            Button(action: redo) { Image(systemName: "arrow.uturn.forward") }.disabled(!canRedo).help("重做 ⇧⌘Z")
            Button(action: preview) { Image(systemName: "text.viewfinder") }.help("预览、OCR、翻译、图片理解与保存")
            Button(action: cancel) { Image(systemName: "xmark") }.help("取消 Esc")
            Button(action: complete) { Image(systemName: "checkmark") }.help("复制图片 ↩ / ⌘C · 保存 PNG 并复制路径 ⇧↩ · P 贴图")
        }
        .buttonStyle(DesignButtonStyle(variant: .ghost))
        .padding(Tokens.Space.sm).background(p.card, in: Capsule())
        .overlay(Capsule().stroke(p.line, lineWidth: Tokens.Size.hairline))
        .font(Tokens.Typography.font()).foregroundStyle(p.foreground)
    }
}
