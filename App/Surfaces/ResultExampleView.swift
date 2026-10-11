import SwiftUI

/// U2 pipeline example only. Full result-window interactions belong to U3.
struct ResultExampleView: View {
    let model: ResultExample
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: Tokens.Space.lg) {
            HStack(spacing: Tokens.Space.sm) {
                Image(systemName: "character.bubble").foregroundStyle(p.accent)
                Text("翻译").font(Tokens.Typography.font(weight: .semibold))
                Text("英文 → 中文").foregroundStyle(p.secondary)
                Spacer()
                Chip(text: "示例")
            }
            VStack(alignment: .leading, spacing: Tokens.Space.sm) {
                Text(model.result + (model.status == .streaming ? " ▍" : ""))
                    .font(Tokens.Typography.font(Tokens.Typography.read))
                    .lineSpacing(Tokens.Typography.readingSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: Tokens.Size.row * 2, alignment: .topLeading)

            Rectangle().fill(p.line).frame(height: Tokens.Size.stroke)
            // Always expanded in this fixture to exercise secondary type and mixed scripts.
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text("原文 · 示例应用 · 直接读取")
                    .font(Tokens.Typography.font(Tokens.Typography.caption))
                    .foregroundStyle(p.tertiary)
                Text(model.source).font(Tokens.Typography.font(Tokens.Typography.meta))
                    .foregroundStyle(p.secondary).fixedSize(horizontal: false, vertical: true)
            }
            StatusLine(status: model.status, detail: model.detail)
            HStack(spacing: Tokens.Space.sm) {
                Kbd(model.status == .streaming ? "Esc 停止" : "↩ 复制并返回")
                if model.status == .done { Kbd("C 复制") }
                Spacer()
                Text("静态预览").font(Tokens.Typography.font(Tokens.Typography.caption))
                    .foregroundStyle(p.tertiary)
            }
        }
        .padding(Tokens.Space.lg)
        .frame(width: Tokens.Size.resultWidth)
        .frame(minHeight: Tokens.Size.resultMinHeight)
        .modifier(DesignSurface())
        .accessibilityLabel("结果浮窗示例，" + model.status.rawValue)
    }
}
