import SwiftUI

struct ScreenshotPreviewContent: View {
    @Bindable var session: ScreenshotSession
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            HStack {
                Label("图片 · " + session.origin, systemImage: "photo")
                if let image = session.image { Text("\(image.width) × \(image.height)").foregroundStyle(p.secondary) }
                Spacer()
                Button { session.close() } label: { Image(systemName: "xmark") }.accessibilityLabel("关闭图片预览")
            }
            if let image = session.image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxHeight: Tokens.Size.control * 10)
                    .accessibilityLabel(session.confirmingImage ? "即将发送给视觉模型的图片" : "原始分辨率合成预览")
            }
            if session.confirmingImage {
                Notice(text: "确认后将把上方图片发送给 \(session.visionModel ?? "视觉模型")。")
                HStack {
                    Button("取消") { session.cancel() }
                    Button("确认发送图片") { session.confirmImage() }.buttonStyle(DesignButtonStyle(variant: .primary))
                }
            } else {
                HStack(spacing: Tokens.Space.sm) {
                    Button("识别文字") { session.runOCR() }.disabled(session.busy)
                    Button("解释图片") { session.prepareImage() }.disabled(session.busy || session.visionModel == nil)
                    Spacer()
                    Button("复制图片") { session.copyImage() }
                    Button("另存为") { session.save() }
                }
                if session.visionModel == nil {
                    Notice(text: "图片能力尚未验证可用。本机识别不受影响。", tone: .warn)
                    Button("配置并测试视觉模型") { session.configureVision() }
                }
                if session.ocrFinished {
                    HStack { Text("识别结果 · 可直接修改"); Spacer(); Chip(text: "本机 · 未上传", tone: .ok) }
                    DesignTextArea(title: "识别结果", text: $session.text).frame(height: Tokens.Size.row * 4)
                    HStack {
                        Button("翻译") { session.runText(templateID: "translate") }
                        Button("总结") { session.runText(templateID: "summarize") }
                        Spacer()
                        Button("复制文字") { session.copyText(session.text) }
                    }.disabled(session.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.busy)
                }
                if session.busy { Button("取消操作") { session.cancel() } }
                Button("完成并复制") { session.copyImage(closeAfter: true) }.keyboardShortcut(.defaultAction)
            }
            if let notice = session.notice { Notice(text: notice) }
        }
        .buttonStyle(DesignButtonStyle(variant: .secondary))
        .padding(Tokens.Space.md).frame(width: Tokens.Size.resultMaxHeight)
        .modifier(DesignSurface()).onExitCommand { session.close() }
    }
}

/// Uses the same design tokens as the result surface, without coupling to the Gallery mock state.
struct ScreenshotResultContent: View {
    @Bindable var session: ScreenshotSession
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            HStack { Text("截图结果"); Spacer(); Text(session.engine); Button("关闭", action: close) }
            ScrollView { Text(session.result).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(minHeight: Tokens.Size.row * 5, maxHeight: Tokens.Size.resultMaxHeight)
            if let notice = session.notice { Notice(text: notice) }
            HStack {
                if session.busy { ProgressView().controlSize(.small); Button("取消") { session.cancel() } }
                Spacer()
                Button("复制") { session.copyText(session.result) }.disabled(session.result.isEmpty)
            }
        }.padding(Tokens.Space.md).frame(width: Tokens.Size.resultWidth)
            .modifier(DesignSurface()).onExitCommand(perform: close)
    }
}
