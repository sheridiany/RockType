import SwiftUI
import RoarkTPlatform
import RoarkTCore

struct ScreenshotPreviewContent: View {
    static var width: CGFloat { min(960, (NSScreen.main?.visibleFrame.width ?? 1120) - 64) }
    static var height: CGFloat { min(760, (NSScreen.main?.visibleFrame.height ?? 840) - 64) }
    @Bindable var session: ScreenshotSession
    var viewport: CGSize? = nil
    @State private var selectedLine: Int?
    @State private var showBoxes = true
    @State private var showVisual = true
    @State private var imageExpanded = false
    @Environment(\.colorScheme) private var scheme
    private var p: Tokens.Palette { Tokens.palette(scheme) }
    private var canUseText: Bool { !session.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.busy }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(Tokens.Space.lg)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.lg) {
                    imagePreview
                    if session.confirmingImage { ScreenshotVisualAIConfirmation(session: session) }
                    else {
                        controls
                        visualActions
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: Tokens.Space.md) {
                                sourceColumn.frame(minWidth: 300)
                                resultColumn.frame(minWidth: 300)
                            }
                            VStack(spacing: Tokens.Space.md) { sourceColumn; resultColumn }
                        }
                    }
                    if let notice = session.notice, !session.busy {
                        Label(notice, systemImage: session.ocrPhase == .failed ? "exclamationmark.circle" : "info.circle")
                            .font(.system(size: 12)).foregroundStyle(session.ocrPhase == .failed ? p.warn : p.secondary)
                            .textSelection(.enabled)
                    }
                }.padding(Tokens.Space.lg)
            }
            Divider()
            footer.padding(.horizontal, Tokens.Space.lg).padding(.vertical, Tokens.Space.sm)
        }
        .frame(width: viewport?.width ?? Self.width, height: viewport?.height ?? Self.height)
        .modifier(DesignSurface())
        .onExitCommand { session.close() }
        .onChange(of: session.ocrFinished) { _, finished in if !finished { selectedLine = nil } }
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.viewfinder").font(.system(size: 21, weight: .medium)).foregroundStyle(p.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("图片与文字").font(.system(size: 15, weight: .semibold))
                HStack(spacing: 6) {
                    Text(session.origin).lineLimit(1)
                    if let image = session.image { Text("·  \(image.width) × \(image.height)").monospacedDigit() }
                }.font(.system(size: 11)).foregroundStyle(p.secondary)
            }
            Spacer(minLength: 8)
            Chip(text: "本机 OCR", tone: .ok)
            Button { session.close() } label: { Image(systemName: "xmark") }
                .buttonStyle(DesignButtonStyle(variant: .ghost)).accessibilityLabel("关闭图片与文字")
        }
    }
    @ViewBuilder private var imagePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("原图对照").font(.system(size: 12, weight: .medium))
                if !session.confirmingImage {
                    Button(imageExpanded ? "收起原图" : "展开原图") { imageExpanded.toggle() }
                        .buttonStyle(.link).font(.system(size: 11))
                }
                Spacer()
                if session.ocrFinished {
                    Toggle("文字框", isOn: $showBoxes).toggleStyle(.checkbox).font(.system(size: 11))
                }
            }.foregroundStyle(p.secondary)
            if let image = session.image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                    .overlay {
                        if showBoxes && session.ocrFinished {
                            GeometryReader { geometry in
                                ForEach(Array(session.ocrLines.enumerated()), id: \.offset) { index, line in
                                    let r = line.rect
                                    Button { selectedLine = index } label: {
                                        Rectangle().fill(p.accent.opacity(selectedLine == index ? 0.24 : 0.035))
                                            .border(p.accent.opacity(selectedLine == index ? 1 : 0.5), width: selectedLine == index ? 2 : 1)
                                    }.buttonStyle(.plain)
                                        .frame(width: r.width * geometry.size.width, height: r.height * geometry.size.height)
                                        .position(x: r.midX * geometry.size.width, y: r.midY * geometry.size.height)
                                        .accessibilityLabel("对照识别区域 \(index + 1)")
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: session.confirmingImage ? 190 : (imageExpanded ? 300 : 110))
                    .accessibilityLabel(session.confirmingImage ? "即将发送的图片" : "原图，可点击文字框对照")
            }
            if let selectedLine, session.ocrLines.indices.contains(selectedLine) {
                Text(session.ocrLines[selectedLine].text).font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled).foregroundStyle(p.foreground).lineLimit(3)
            }
        }
        .padding(Tokens.Space.md).frame(maxWidth: .infinity)
        .background(p.cardSecondary, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).stroke(p.line, lineWidth: 1))
    }
    private var controls: some View {
        HStack(spacing: 8) {
            Button { session.runOCR() } label: {
                Label(session.ocrFinished ? "重新识别" : "识别文字", systemImage: "text.viewfinder")
            }.buttonStyle(DesignButtonStyle(variant: .primary)).disabled(session.busy)
                .keyboardShortcut("r", modifiers: .command)
            Menu("语言") {
                ForEach(["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"], id: \.self) { language in
                    Toggle(languageName(language), isOn: Binding(get: { session.ocrLanguages.contains(language) }, set: { enabled in
                        if enabled { session.ocrLanguages.append(language) }
                        else { session.ocrLanguages.removeAll { $0 == language } }
                    }))
                }
            }.help("选择优先识别语言，同时自动检测其他语言").disabled(session.busy)
            Toggle("合并段落", isOn: $session.mergeParagraphs).toggleStyle(.checkbox).font(.system(size: 12))
                .help("下次识别时合并正文；表格、代码保留原有布局").disabled(session.busy)
            Spacer(minLength: 0)
            if session.busy {
                ProgressView().controlSize(.small)
                Button("取消") { session.cancel() }.buttonStyle(DesignButtonStyle(variant: .ghost))
            }
        }
    }
    private var sourceColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("识别原文", systemImage: "text.alignleft").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("可编辑").font(.system(size: 11)).foregroundStyle(p.secondary)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $session.text).font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(5)
                    .disabled(session.busy).accessibilityLabel("识别原文，可编辑")
                if session.text.isEmpty {
                    placeholder(icon: sourceIcon, title: sourceTitle, detail: sourceDetail)
                        .allowsHitTesting(false).padding(.top, 24)
                }
            }.frame(height: 210).background(p.canvas, in: RoundedRectangle(cornerRadius: 7))
            HStack {
                Button("复制原文") { session.copyText(session.text) }.disabled(!canUseText)
                Button("仅文字翻译") { showVisual = false; session.translate() }.disabled(!canUseText)
                Spacer()
                Text("\(session.text.count) 字").font(.system(size: 11)).monospacedDigit().foregroundStyle(p.secondary)
            }.buttonStyle(DesignButtonStyle(variant: .secondary))
        }.padding(Tokens.Space.md).background(p.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).stroke(p.line, lineWidth: 1))
    }
    private var translationColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("译文", systemImage: "character.bubble").font(.system(size: 13, weight: .semibold))
                Spacer()
                if session.translation.phase == .running { ProgressView().controlSize(.small) }
                Text(session.translation.engine.isEmpty ? "按需翻译" : session.translation.engine)
                    .font(.system(size: 11)).foregroundStyle(p.secondary).lineLimit(1)
            }
            ScrollView {
                if session.translation.text.isEmpty {
                    placeholder(icon: session.translation.phase == .failed ? "exclamationmark.bubble" : "character.book.closed",
                        title: translationTitle, detail: session.translation.notice ?? "核对左侧文字后点击翻译，译文会显示在这里。")
                        .padding(.top, 24)
                } else {
                    Text(session.translation.text).font(.system(size: 14)).lineSpacing(5)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(10)
                }
            }.frame(height: 210).frame(maxWidth: .infinity)
                .background(p.canvas, in: RoundedRectangle(cornerRadius: 7))
            HStack {
                if session.translation.phase == .running {
                    Button("取消翻译") { session.translation.cancel() }
                } else {
                    Button(session.translation.phase == .failed ? "重试翻译" : "翻译原文") { session.translate() }
                        .disabled(!canUseText)
                }
                Button("复制译文") { session.copyText(session.translation.text) }
                    .disabled(session.translation.phase != .done)
                Spacer(minLength: 0)
            }.buttonStyle(DesignButtonStyle(variant: .secondary))
        }.padding(Tokens.Space.md).background(p.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).stroke(p.line, lineWidth: 1))
    }
    private func placeholder(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 23)).foregroundStyle(p.tertiary)
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(p.foreground)
            Text(detail).font(.system(size: 12)).foregroundStyle(p.secondary).multilineTextAlignment(.center)
        }.padding(.horizontal, 20).frame(maxWidth: .infinity)
    }
    private var sourceIcon: String { session.ocrPhase == .failed ? "exclamationmark.circle" : "text.viewfinder" }
    private var sourceTitle: String {
        switch session.ocrPhase {
        case .running: "正在本机识别…"
        case .empty: "没有找到清晰文字"
        case .failed: "识别未完成"
        case .cancelled: "识别已取消"
        default: "从图片中提取文字"
        }
    }
    private var sourceDetail: String {
        switch session.ocrPhase {
        case .running: "完成后可直接核对和修改。"
        case .empty: "尝试更清晰的图片，或在这里直接输入文字。"
        case .failed: "点击重新识别再试一次，也可直接输入文字。"
        default: "点击识别文字。OCR 在本机运行，图片不会上传。"
        }
    }
    private var translationTitle: String {
        switch session.translation.phase {
        case .running: session.translation.thinking ? "思考中…" : "正在翻译…"
        case .failed: "翻译未完成"
        case .cancelled: "翻译已取消"
        default: "原文与译文并排对照"
        }
    }
    @ViewBuilder private var resultColumn: some View {
        if showVisual { ScreenshotVisualAIResult(session: session) }
        else { translationColumn }
    }
    private var visualActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("结果类型", selection: $showVisual) {
                    Text("图片 AI").tag(true)
                    Text("仅文字翻译").tag(false)
                }.pickerStyle(.segmented).frame(width: 250)
                Spacer()
            }
            if showVisual {
                HStack {
                    Button("截图翻译…") { session.prepareImage(action: .translate) }
                    Button("截图总结…") { session.prepareImage(action: .summarize) }
                    Button("理解图片…") { session.prepareImage(action: .explain) }
                    Spacer(minLength: 0)
                }.buttonStyle(DesignButtonStyle(variant: .secondary)).disabled(session.busy || session.visionModel == nil)
                if session.visionModel == nil {
                    Button("配置并验证视觉模型，以使用图片 AI") { session.configureVision() }
                        .buttonStyle(.link).font(.system(size: 12))
                }
            }
        }
    }
    private var footer: some View {
        HStack {
            Menu("图片操作") {
                Button("复制图片") { session.copyImage() }
                Button("另存为…") { session.save() }
                Button("贴图") { session.pinImage() }
                Divider()
                Button("解释图片…") { showVisual = true; session.prepareImage() }.disabled(session.visionModel == nil || session.busy)
                Button("配置视觉模型…") { session.configureVision() }
                Button("恢复图片 AI 每次发送确认") { session.restoreImageConfirmation() }
            }.fixedSize()
            Spacer()
            Text(showVisual ? "图片 AI 会发送图片与识别文字" : "仅文字翻译不发送图片").font(.system(size: 11)).foregroundStyle(p.secondary)
            Button("关闭") { session.close() }.buttonStyle(DesignButtonStyle(variant: .secondary))
        }
    }
    private func languageName(_ code: String) -> String {
        ["zh-Hans": "简体中文", "zh-Hant": "繁體中文", "en-US": "English", "ja-JP": "日本語", "ko-KR": "한국어"][code] ?? code
    }
}
