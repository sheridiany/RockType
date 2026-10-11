import SwiftUI
import Translation

struct LanguagePackStepView: View {
    let model: LanguagePackModel
    @State private var preparing = false
    @State private var direction = 0
    var body: some View {
        Label("简体中文 ↔ English", systemImage: "arrow.left.arrow.right")
        Notice(text: model.state.message, tone: model.state == .installed ? .ok : .neutral)
        HStack {
            Button("重新检查") { Task { await model.refresh() } }
                .disabled(preparing || model.state == .checking).buttonStyle(DesignButtonStyle())
            if #available(macOS 26, *), model.state == .available || model.state == .failed {
                Button("准备语言包") { direction = 0; preparing = true }
                    .disabled(preparing).buttonStyle(DesignButtonStyle(variant: .primary))
            }
            if preparing {
                Button("取消") { preparing = false; model.preparationFailed() }.buttonStyle(DesignButtonStyle())
            }
        }
        if #available(macOS 26, *), preparing {
            LanguagePackPreparation(direction: direction) { success in
                guard preparing else { return }
                if success && direction == 0 { direction = 1 }
                else {
                    preparing = false
                    if success { await model.refresh() } else { model.preparationFailed() }
                }
            }.id(direction)
        }
        Text("只有点击准备后才请求系统下载；不会发送试打内容。")
            .font(Tokens.Typography.font(Tokens.Typography.caption))
            .task { await model.refresh() }
    }
}

@available(macOS 26, *)
private struct LanguagePackPreparation: View {
    let direction: Int
    let completed: @MainActor (Bool) async -> Void
    var body: some View {
        Text("正在准备\(direction == 0 ? "中译英" : "英译中")语言包…")
            .translationTask(source: .init(identifier: direction == 0 ? "zh-Hans" : "en"),
                             target: .init(identifier: direction == 0 ? "en" : "zh-Hans")) { @Sendable session in
                do {
                    try await session.prepareTranslation()
                    guard !Task.isCancelled else { return }
                    await completed(true)
                } catch {
                    guard !Task.isCancelled else { return }
                    await completed(false)
                }
            }
    }
}
