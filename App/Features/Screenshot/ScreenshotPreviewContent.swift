import SwiftUI
import RoarkTPlatform

struct ScreenshotPreviewContent: View {
    static var height: CGFloat { min(760, (NSScreen.main?.visibleFrame.height ?? 840) - 80) }
    @Bindable var session: ScreenshotSession
    @State private var selectedLine: Int?
    @State private var showBoxes = true
    @Environment(\.colorScheme) private var scheme
    private func languageName(_ code: String) -> String {
        ["zh-Hans": "简体中文", "zh-Hant": "繁體中文", "en-US": "English", "ja-JP": "日本語", "ko-KR": "한국어"][code] ?? code
    }
    var body: some View {
        let p = Tokens.palette(scheme)
        ScrollView {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            HStack {
                Label("图片 · " + session.origin, systemImage: "photo")
                if let image = session.image { Text("\(image.width) × \(image.height)").foregroundStyle(p.secondary) }
                Spacer()
                Button { session.close() } label: { Image(systemName: "xmark") }.accessibilityLabel("关闭图片预览")
            }
            if let image = session.image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                    .overlay {
                        if showBoxes && session.ocrFinished {
                            GeometryReader { geometry in
                                ForEach(Array(session.ocrLines.enumerated()), id: \.offset) { index, line in
                                    let r = line.rect
                                    Button { selectedLine = index } label: {
                                        Rectangle().fill(Color.accentColor.opacity(selectedLine == index ? 0.25 : 0.06))
                                            .border(Color.accentColor.opacity(0.8), width: selectedLine == index ? 2 : 1)
                                    }.buttonStyle(.plain)
                                        .frame(width: r.width * geometry.size.width, height: r.height * geometry.size.height)
                                        .position(x: r.midX * geometry.size.width, y: r.midY * geometry.size.height)
                                        .accessibilityLabel("识别区域 \(index + 1)")
                                }
                            }
                        }
                    }
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
                HStack {
                    Menu("识别语言") {
                        ForEach(["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"], id: \.self) { language in
                            Toggle(languageName(language), isOn: Binding(get: { session.ocrLanguages.contains(language) }, set: { enabled in
                                if enabled { session.ocrLanguages.append(language) }
                                else { session.ocrLanguages.removeAll { $0 == language } }
                            }))
                        }
                    }.help("本次图片的优先识别语言；同时自动检测其他语言")
                    Toggle("合并段落", isOn: $session.mergeParagraphs).toggleStyle(.checkbox)
                        .help("下次识别时合并连续正文；代码和列表建议保留逐行格式")
                    Spacer()
                }
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
                    Toggle("显示文字框", isOn: $showBoxes).toggleStyle(.checkbox)
                    if let selectedLine, session.ocrLines.indices.contains(selectedLine) {
                        Text(session.ocrLines[selectedLine].text).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(p.pill, in: RoundedRectangle(cornerRadius: 6))
                    }
                    TextEditor(text: $session.text).font(.system(.body, design: .monospaced))
                        .accessibilityLabel("识别结果，可编辑").frame(height: Tokens.Size.row * 4)
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
        .padding(Tokens.Space.md)
        }
        .frame(width: Tokens.Size.resultMaxHeight, height: Self.height)
        .modifier(DesignSurface()).onExitCommand { session.close() }
    }
}
