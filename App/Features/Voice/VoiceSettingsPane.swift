import SwiftUI
import RoarkTCore

struct VoiceSettingsPane: View {
    @Binding var settings: VoiceSettings
    let aiConfigured: Bool
    @ObservedObject private var models = VoiceModelStore.shared
    private var model: VoiceModel { VoiceModel(settings.model) }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            U4Card {
                Picker("识别模型", selection: $settings.model) {
                    Text(VoiceModel.small.title).tag(VoiceSettings.Model.small)
                    Text(VoiceModel.large.title).tag(VoiceSettings.Model.large)
                }.disabled(models.busy)
                Text("下载大小不等于运行内存。1.7B 通常占用更多内存；本机内存峰值、冷启动与识别延迟待实测，不承诺固定速度。")
                    .font(Tokens.Typography.font(Tokens.Typography.caption))
                if let progress = models.progress {
                    ProgressView(value: progress).accessibilityLabel("模型下载进度")
                }
                Text(models.message).font(Tokens.Typography.font(Tokens.Typography.caption))
                    .accessibilityLabel("模型状态：" + models.message)
                HStack {
                    if models.busy {
                        Button("取消下载") { models.cancel() }
                    } else {
                        Button(models.isPresent(model) ? "重新下载并校验" : "下载模型") { models.download(model) }
                        Button("删除此模型", role: .destructive) { models.remove(model) }
                    }
                }
            }
            U4Card {
                Toggle("选中 RockType 输入法时自动准备模型", isOn: $settings.automaticallyPrepareModel)
                Text("只加载已下载模型，不开启麦克风；关闭后释放模型内存。")
                    .font(Tokens.Typography.font(Tokens.Typography.caption))
                Toggle("AI 润色语音结果", isOn: $settings.polishWithAI).disabled(!aiConfigured)
                Text(aiConfigured ? "开启后发送本次识别文本给所配置的 AI；失败时使用原文。" : "请先配置 AI 连接，才能启用润色。")
                    .font(Tokens.Typography.font(Tokens.Typography.caption))
            }
            Notice(text: "按住 Fn 说话，松开识别；Esc 取消。不自动发送。请在系统键盘设置中检查 Fn 与听写、输入源切换的冲突；RockType 不会更改系统快捷键。")
        }
    }
}
