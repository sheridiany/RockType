import SwiftUI

struct SelectionToolbarView: View {
    let model: SelectionToolbarModel
    @Environment(\.colorScheme) private var scheme
    @State private var copied = false
    @State private var selectedAction: SurfaceAction?
    var body: some View {
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            if model.isVisible {
                HStack(spacing: Tokens.Space.xs) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .foregroundStyle(p.accent).padding(.horizontal, Tokens.Space.sm)
                        .accessibilityHidden(true)
                    Rectangle().fill(p.line).frame(width: Tokens.Size.stroke, height: Tokens.Size.compact)
                    ForEach(model.actions, id: \.self) { action in
                        let isCopied = action == .copy && (copied || model.state == .copied)
                        Button {
                            if action == .copy { copied = true } else { selectedAction = action }
                        } label: {
                            HStack(spacing: Tokens.Space.xs) {
                                Image(systemName: isCopied ? "checkmark" : action.symbol)
                                if !model.compact { Text(isCopied ? "已复制" : action.title) }
                            }
                        }
                        .buttonStyle(DesignButtonStyle(variant: .ghost))
                        .disabled(model.disabledReason(for: action) != nil)
                        .accessibilityLabel(isCopied ? "已复制" : action.title)
                        .help(model.disabledReason(for: action) ?? action.title)
                    }
                }.padding(Tokens.Space.xs).modifier(DesignSurface())
                if model.state == .unconfigured {
                    Notice(text: "解释和总结需要配置 AI；本地翻译、搜索和复制仍可用。", tone: .warn)
                }
                if let selectedAction { Notice(text: "已选择" + selectedAction.title) }
            } else {
                // Gallery explanation only: no selectable content or actionable toolbar.
                Notice(text: "当前为安全输入区域，划词工具栏已隐藏。不会读取或处理内容。")
            }
        }
        .frame(width: model.compact ? Tokens.Size.menuWidth : Tokens.Size.resultWidth)
        .accessibilityLabel("划词工具栏 · " + model.state.title)
    }
}
