import SwiftUI

struct MenuBarPanelView: View {
    let model: MenuBarPanelModel
    @Environment(\.colorScheme) private var scheme
    @State private var showAll = false
    @State private var cleared = false
    @State private var feedback: String?

    private var recent: [MenuBarPanelModel.Recent] { cleared ? [] : model.recent }
    private var aiLabel: String {
        switch model.ai {
        case .ready: "AI 可用 · " + model.model
        case .unconfigured: "AI 未配置"
        case .error: "AI 连接异常"
        }
    }
    private var aiTone: DesignTone {
        switch model.ai { case .ready: .ok; case .unconfigured: .neutral; case .error: .danger }
    }
    var body: some View {
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            HStack {
                Label("RockType", systemImage: "square.stack.3d.up")
                    .font(Tokens.Typography.font(Tokens.Typography.read, weight: .semibold))
                Spacer()
                Button { feedback = "设置入口已选中" } label: { Image(systemName: "gearshape") }
                    .buttonStyle(DesignButtonStyle(variant: .ghost)).accessibilityLabel("设置")
            }
            if let time = model.beijingTime {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text(time).font(Tokens.Typography.font(Tokens.Typography.display, weight: .semibold))
                        .monospacedDigit()
                    Text("北京 · " + model.beijingDate)
                        .font(Tokens.Typography.font(Tokens.Typography.meta)).foregroundStyle(p.secondary)
                    if let local = model.localTime {
                        Text(local).font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(Tokens.Space.md)
                .background(p.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            } else {
                HStack {
                    Text("最近结果").font(Tokens.Typography.font(weight: .medium))
                    Spacer()
                    Chip(text: aiLabel, tone: aiTone)
                }
            }
            ActionRow(title: "截图", symbol: "viewfinder", shortcut: "⌃1") { feedback = "截图编辑器入口已选中" }
                .background(p.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            HStack {
                Text(model.beijingTime == nil ? "本次运行" : "最近结果")
                    .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
                Spacer()
                if !recent.isEmpty {
                    Button("清除") { cleared = true; feedback = nil }
                        .buttonStyle(DesignButtonStyle(variant: .ghost))
                }
            }
            if recent.isEmpty {
                Text("本次运行的结果暂存在这里，退出后清空。")
                    .font(Tokens.Typography.font(Tokens.Typography.meta)).foregroundStyle(p.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.vertical, Tokens.Space.sm)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.prefix(showAll ? 10 : 5))) { item in
                        ActionRow(title: item.excerpt, symbol: item.action.symbol, shortcut: item.age) {
                            feedback = "已打开最近的" + item.action.title + "结果"
                        }.lineLimit(1).help(item.excerpt)
                    }
                    if recent.count > 5 {
                        Button(showAll ? "收起" : "显示全部 \(recent.count) 条") { showAll.toggle() }
                            .buttonStyle(DesignButtonStyle(variant: .ghost))
                    }
                }.background(p.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            }
            if let feedback { Notice(text: feedback) }
            HStack(spacing: Tokens.Space.sm) {
                if model.beijingTime != nil { Chip(text: aiLabel, tone: aiTone) }
                Spacer(minLength: 0)
                Button("设置") { feedback = "设置入口已选中" }.keyboardShortcut(",")
                Kbd("⌘,")
                Button("退出") { feedback = "退出操作已选择；设计面板继续保留" }
                Kbd("⌘Q")
            }.buttonStyle(DesignButtonStyle(variant: .ghost))
        }
        .padding(Tokens.Space.md).frame(width: Tokens.Size.menuWidth)
        .modifier(DesignSurface()).accessibilityLabel("菜单栏面板")
    }
}
