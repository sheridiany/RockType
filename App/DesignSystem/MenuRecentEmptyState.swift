import SwiftUI

struct MenuRecentEmptyState: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            Label("还没有最近结果", systemImage: "text.bubble")
                .font(Tokens.Typography.font(weight: .medium))
            Text("完成翻译或 AI 操作后可在这里重新打开。内容仅在本次运行中保留，退出即清空。")
                .font(Tokens.Typography.font(Tokens.Typography.meta))
                .foregroundStyle(Tokens.palette(scheme).secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(Tokens.Space.md).frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.palette(scheme).card, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .accessibilityElement(children: .combine)
    }
}
