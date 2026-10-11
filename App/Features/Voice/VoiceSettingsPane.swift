import SwiftUI
import RoarkTCore

struct VoiceSettingsPane: View {
    @Binding var settings: VoiceSettings
    let aiConfigured: Bool
    @ObservedObject private var models = VoiceModelStore.shared
    private var model: VoiceModel { VoiceModel(settings.model) }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            DesignCard {
                Picker("识别模型", selection: $settings.model) {
                    Text(VoiceModel.small.title).tag(VoiceSettings.Model.small)
                    Text(VoiceModel.large.title).tag(VoiceSettings.Model.large)
                }.disabled(models.busy)
                Text("下载大小不等于运行内存。1.7B 通常占用更多内存；本机内存峰值、冷启动与识别延迟待实测，不承诺固定速度。")
                    .font(Tokens.Typography.font(Tokens.Typography.caption))
                    .foregroundStyle(.secondary)
                if let progress = models.progress {
                    ProgressView(value: progress).accessibilityLabel("模型下载进度")
                }
                Text(models.message).font(Tokens.Typography.font(Tokens.Typography.caption))
                    .foregroundStyle(.secondary)
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
            DesignCard {
                option("自动准备模型", detail: "选中 RockType 输入法时加载已下载模型，不开启麦克风；关闭后释放模型内存。", value: $settings.automaticallyPrepareModel)
                Divider()
                option("本地文字清理", detail: "去除独立口头填充词、合并多余空格并补中文句号。在本机完成，无需 AI。", value: $settings.cleanUpLocally)
                Divider()
                option("AI 润色语音结果", detail: aiConfigured
                       ? "将本次识别文字发送给已配置的 AI；失败时保留原文。"
                       : "先在 AI 连接中配置服务商，才能启用润色。",
                       value: $settings.polishWithAI, enabled: aiConfigured)
            }
            Notice(text: "按住 Fn 说话，松开识别；Esc 取消。不自动发送。请在系统键盘设置中检查 Fn 与听写、输入源切换的冲突；RockType 不会更改系统快捷键。")
        }
    }

    private func option(_ title: String, detail: String, value: Binding<Bool>, enabled: Bool = true) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(detail)
                    .font(Tokens.Typography.font(Tokens.Typography.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Tokens.Space.md)
            Toggle(title, isOn: value)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!enabled)
                .accessibilityLabel(title)
                .accessibilityHint(detail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}
