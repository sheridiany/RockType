import SwiftUI

/// Production preview wrapper. No prototype state or synthetic image is initialized.
struct ImagePreviewView: View {
    let session: ScreenshotSession
    var body: some View { ScreenshotPreviewContent(session: session) }
}

#if DEBUG

struct ImagePreviewPrototype: View {
    @State private var model: ImagePreviewModel
    @State private var text: String
    @State private var feedback: String?
    let rendering: Bool
    @Environment(\.colorScheme) private var scheme
    init(model: ImagePreviewModel, rendering: Bool = false) {
        self.rendering = rendering
        _model = State(initialValue: model)
        _text = State(initialValue: model.recognizedText)
    }
    var body: some View {
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            HStack(spacing: Tokens.Space.sm) {
                Label("图片", systemImage: "photo")
                    .font(Tokens.Typography.font(Tokens.Typography.read, weight: .medium))
                if model.hasImage {
                    Text("\(model.pixelWidth) × \(model.pixelHeight) · " + model.origin)
                        .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
                }
                Spacer(minLength: 0)
                Button { feedback = "图片预览已关闭" } label: { Image(systemName: "xmark") }
                    .buttonStyle(DesignButtonStyle(variant: .ghost)).accessibilityLabel("关闭图片预览")
            }
            if !model.hasImage {
                VStack(spacing: Tokens.Space.md) {
                    Image(systemName: "lock.shield").font(Tokens.Typography.font(Tokens.Typography.display)).foregroundStyle(p.warn)
                    Text("需要“屏幕录制”权限才能截图").font(Tokens.Typography.font(weight: .semibold))
                    Text("授权后可重新截图。也可以使用剪贴板中的图片，继续在本机识别文字。")
                        .foregroundStyle(p.secondary).multilineTextAlignment(.center)
                    Button("打开系统设置") { feedback = "屏幕录制权限入口已选中" }
                        .buttonStyle(DesignButtonStyle(variant: .primary))
                    Button("使用剪贴板图片") {
                        model.state = .clipboard; model.origin = "剪贴板图片"; model.imageLines = SurfaceSampleText.imageLines
                    }.buttonStyle(DesignButtonStyle(variant: .secondary))
                }.frame(maxWidth: .infinity).padding(Tokens.Space.xxl)
                    .background(p.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            } else {
                SyntheticCapturePreview(lines: model.imageLines)
                    .aspectRatio(CGFloat(model.pixelWidth) / CGFloat(model.pixelHeight), contentMode: .fit)
                    .frame(maxHeight: Tokens.Size.control * 10)
                HStack(spacing: Tokens.Space.sm) {
                    Button("识别文字") { model.state = .ocrDone; text = SurfaceSampleText.ocr; feedback = nil }
                        .keyboardShortcut("r").disabled(model.state == .ocrRunning)
                        .buttonStyle(DesignButtonStyle(variant: model.state == .preview || model.state == .noVision || model.state == .clipboard || model.state == .drop ? .primary : .secondary))
                    Button("解释图片") { feedback = "图片内容：预览服务已在运行，可停止旧预览后重试。" }
                        .disabled(!model.visionAvailable || model.state == .ocrRunning)
                        .buttonStyle(DesignButtonStyle(variant: .secondary))
                    Spacer(minLength: 0)
                    Button("复制图片") { feedback = "图片已复制" }.keyboardShortcut("c")
                        .buttonStyle(DesignButtonStyle(variant: .ghost))
                    Button("另存为") { feedback = "已选择另存为（演示不写入文件）" }.keyboardShortcut("s")
                        .buttonStyle(DesignButtonStyle(variant: .ghost))
                }
                switch model.state {
                case .noVision:
                    Notice(text: "当前模型不支持图片。识别文字在本机完成，仍然可用。", tone: .warn)
                    Button("配置视觉模型") { feedback = "视觉模型配置入口已选中" }
                        .buttonStyle(DesignButtonStyle(variant: .secondary))
                case .ocrRunning:
                    Label("本机识别中…", systemImage: "text.viewfinder").foregroundStyle(p.accent)
                    Button("取消识别") { model.state = .preview; feedback = "已取消识别" }
                        .buttonStyle(DesignButtonStyle(variant: .ghost))
                case .ocrEmpty:
                    Notice(text: "没有识别到文字。可换用更清晰的图片，或尝试解释图片。", tone: .warn)
                case .ocrDone:
                    VStack(alignment: .leading, spacing: Tokens.Space.sm) {
                        HStack {
                            Text("识别结果").font(Tokens.Typography.font(weight: .medium))
                            Chip(text: "本机识别 · 未上传", tone: .ok)
                            Spacer(minLength: 0)
                            Text("可直接修改").font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
                        }
                        Group {
                            if rendering {
                                Text(text).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(Tokens.Space.sm).background(p.pill, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                            } else { DesignTextArea(title: "识别结果", text: $text) }
                        }
                            .frame(height: Tokens.Size.row * 4)
                        HStack(spacing: Tokens.Space.sm) {
                            Button("翻译") { feedback = "已选择翻译编辑后的识别结果" }
                            Button("总结") { feedback = "已选择总结编辑后的识别结果" }
                            Spacer(minLength: 0)
                            Button("复制文字") { feedback = "编辑后的文字已复制" }
                        }.buttonStyle(DesignButtonStyle(variant: .secondary))
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.padding(Tokens.Space.md)
                        .background(p.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                default: EmptyView()
                }
            }
            if let feedback { Notice(text: feedback) }
        }
        .padding(Tokens.Space.md)
        // Closest existing dimension to the 480 pt image surface; dedicated token requested in SPEC-002.
        .frame(width: Tokens.Size.resultMaxHeight)
        .modifier(DesignSurface()).accessibilityLabel("图片预览 · " + model.state.title)
    }
}

/// Draws an invented image, never a screen capture or user file.
struct SyntheticCapturePreview: View {
    let lines: [String]
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            HStack {
                Image(systemName: "terminal")
                Text("Preview").font(Tokens.Typography.font(Tokens.Typography.caption))
                Spacer()
                Text("示例图片").font(Tokens.Typography.font(Tokens.Typography.caption))
            }.foregroundStyle(p.secondary)
            Rectangle().fill(p.line).frame(height: Tokens.Size.hairline)
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(line).font(.system(size: Tokens.Typography.meta, design: .monospaced))
                    .foregroundStyle(index == 1 ? p.danger : p.foreground)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }.padding(Tokens.Space.md).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(p.cardSecondary, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).stroke(p.line, lineWidth: Tokens.Size.stroke))
    }
}

#endif
