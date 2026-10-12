import AppKit
import SwiftUI
import RoarkTCore

/// Dedicated source editor: Return commits; Shift-Return inserts a line; IME composition wins.
struct TranslateSourceEditor: NSViewRepresentable {
    let text: String
    let expanded: Bool
    let changed: (String, Bool) -> Void
    let submit: () -> Void
    let focus: () -> Void
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay; scroll.autohidesScrollers = true
        let editor = Editor(); editor.isRichText = false; editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 14); editor.textColor = .labelColor
        editor.textContainerInset = NSSize(width: 0, height: 4)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.lineFragmentPadding = 0
        editor.setAccessibilityLabel("翻译原文")
        editor.changed = changed; editor.submit = submit; editor.focus = focus
        editor.delegate = editor; editor.string = text
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? Editor else { return }
        editor.changed = changed; editor.submit = submit; editor.focus = focus
        if editor.string != text && !editor.hasMarkedText() { editor.string = text }
        editor.textContainer?.containerSize = NSSize(width: max(1, scroll.contentSize.width), height: .greatestFiniteMagnitude)
    }
    final class Editor: NSTextView, NSTextViewDelegate {
        var changed: ((String, Bool) -> Void)?
        var submit: (() -> Void)?
        var focus: (() -> Void)?
        override func mouseDown(with event: NSEvent) { focus?(); super.mouseDown(with: event) }
        func textDidChange(_ notification: Notification) { changed?(string, hasMarkedText()) }
        override func unmarkText() { let marked = hasMarkedText(); super.unmarkText(); if marked { changed?(string, false) } }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36, !hasMarkedText(), event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty {
                submit?(); return
            }
            super.keyDown(with: event)
        }
    }
}

/// Optional actions owned by the window controller.
struct TranslateWindowSlots {
    var replacement: () -> AnyView = { AnyView(EmptyView()) }
    var close: () -> Void = {}
}

struct TranslateWindowView: View {
    @Bindable var state: TranslateWindowState
    let close: () -> Void
    let focusEditor: () -> Void
    let copy: (Bool, Bool) -> Void
    var slots = TranslateWindowSlots()
    var copyCode: (String) -> Void = { _ in }
    var contentHeight: (CGFloat) -> Void = { _ in }
    @State private var sourceWidth: CGFloat = 388
    @FocusState private var questionFocused: Bool
    @Environment(\.colorScheme) private var scheme
    private var p: Tokens.Palette { Tokens.palette(scheme) }
    var body: some View {
        VStack(spacing: 0) {
            header.translationHeight("header")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    source
                    languageBar
                    VStack(alignment: .leading, spacing: Tokens.Space.md) {
                        if let definition = state.definition { WordDefinitionCard(definition: definition, embedded: true) }
                        translation
                        if let notice = state.result.notice {
                            Text(notice).font(Tokens.Typography.font(Tokens.Typography.caption))
                                .foregroundStyle(p.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        if state.followupExpanded {
                            HStack(alignment: .bottom, spacing: Tokens.Space.sm) {
                                TextField("基于这段译文追问", text: Binding(get: { state.result.question }, set: { state.result.question = $0 }), axis: .vertical)
                                    .textFieldStyle(.plain).lineLimit(1...4).focused($questionFocused).onSubmit { state.ask() }
                                Button { state.ask() } label: { Image(systemName: "arrow.up.circle.fill") }
                                    .buttonStyle(TranslateIconButtonStyle()).help("发送追问").accessibilityLabel("发送追问")
                                    .disabled(state.result.isBusy || state.result.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }.padding(Tokens.Space.sm).background(p.canvas, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
                        }
                    }.padding(.horizontal, Tokens.Space.lg).padding(.vertical, Tokens.Space.md)
                }.frame(maxWidth: .infinity).translationHeight("content").background(TranslateScrollStyle())
            }
            Rectangle().fill(p.borderSubtle).frame(height: Tokens.Size.hairline)
            footer.translationHeight("footer")
        }
        .font(Tokens.Typography.font()).foregroundStyle(p.textPrimary).background(p.card)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.window))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.window).strokeBorder(p.borderSubtle, lineWidth: Tokens.Size.hairline))
        .onPreferenceChange(TranslateHeightPreference.self) { parts in
            if parts.count == 3 { contentHeight(ceil(parts.values.reduce(0, +) + Tokens.Size.hairline)) }
        }
    }
    private var header: some View {
        HStack(spacing: Tokens.Space.xs) {
            Label("翻译", systemImage: "character.bubble")
                .font(Tokens.Typography.font(weight: .medium)).foregroundStyle(p.secondary)
            Spacer(minLength: Tokens.Space.sm)
            Button { state.followupExpanded.toggle(); if state.followupExpanded { focusEditor(); questionFocused = true } }
                label: { Image(systemName: state.followupExpanded ? "text.bubble.fill" : "text.bubble") }
                .help("追问").accessibilityLabel("展开或收起追问").disabled(!state.result.canAsk)
            Button(action: state.submit) { Image(systemName: "arrow.clockwise") }.help("重新翻译 ⌘R").accessibilityLabel("重新翻译")
            Button(action: close) { Image(systemName: "xmark") }.help("关闭 Esc").accessibilityLabel("关闭翻译窗")
        }.buttonStyle(TranslateIconButtonStyle())
            .padding(.horizontal, Tokens.Space.lg).padding(.top, Tokens.Space.sm).padding(.bottom, Tokens.Space.xs)
            .background(ResultWindowDragArea())
    }
    private var source: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Tokens.Space.xs) {
                sectionLabel("原文")
                Spacer()
                SpeakButton(speaker: state.sourceSpeaker, text: state.original, compact: true)
                    .accessibilityLabel(state.sourceSpeaker.isActive ? "停止朗读原文" : "朗读原文")
                if state.expanded || TranslateWindowLayout.sourceHeight(state.original, width: sourceWidth, expanded: true)
                    > TranslateWindowLayout.sourceHeight(state.original, width: sourceWidth, expanded: false) {
                    Button { state.expanded.toggle() } label: { Image(systemName: state.expanded ? "chevron.up" : "chevron.down") }
                        .buttonStyle(TranslateIconButtonStyle()).help(state.expanded ? "收起原文" : "展开原文；也可在原文区滚动")
                        .accessibilityLabel(state.expanded ? "收起原文" : "展开原文")
                }
            }
            ZStack(alignment: .topLeading) {
                if state.original.isEmpty {
                    Text("输入要翻译的文字…").font(Tokens.Typography.font(Tokens.Typography.read))
                        .foregroundStyle(p.tertiary).padding(.top, Tokens.Space.xs).allowsHitTesting(false)
                }
                TranslateSourceEditor(text: state.original, expanded: state.expanded,
                    changed: { state.edit($0, composing: $1) }, submit: state.submit, focus: focusEditor)
                    .frame(height: TranslateWindowLayout.sourceHeight(state.original, width: sourceWidth, expanded: state.expanded))
            }
        }.translationWidth { if $0 > 0 { sourceWidth = $0 } }
            .padding(.horizontal, Tokens.Space.lg).padding(.bottom, Tokens.Space.md)
    }
    @ViewBuilder private var translation: some View {
        if state.definition != nil && !state.result.answer.isEmpty && state.result.currentQuestion == nil {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.sm) {
                sectionLabel("译文")
                Text(ResultMarkdown.inline(state.result.answer.replacingOccurrences(of: "\n", with: " ")))
                    .font(Tokens.Typography.font()).foregroundStyle(p.secondary).lineLimit(1)
                    .textSelection(.enabled).help(state.result.answer)
                    .environment(\.openURL, OpenURLAction { url in
                        ["http", "https"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
                    })
                    .frame(maxWidth: .infinity, alignment: .leading)
                if state.result.isBusy {
                    ProgressView().controlSize(.mini)
                    Button { state.result.cancel() } label: { Image(systemName: "stop.fill") }
                        .buttonStyle(TranslateIconButtonStyle()).help("停止翻译").accessibilityLabel("停止翻译")
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Tokens.Space.sm) {
                HStack {
                    sectionLabel("译文")
                    Spacer()
                    if state.result.isBusy { ProgressView().controlSize(.mini) }
                    if state.result.isBusy { Button("停止") { state.result.cancel() }.font(Tokens.Typography.font(Tokens.Typography.caption)).buttonStyle(.plain).help("停止翻译") }
                }
                if state.result.answer.isEmpty {
                    Text(placeholder).font(Tokens.Typography.font(Tokens.Typography.read)).foregroundStyle(p.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ResultAnswerView(text: state.result.answer, markdown: true, copyCode: copyCode)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    private var footer: some View {
        HStack(spacing: Tokens.Space.xs) {
            Menu {
                Button("Apple 优先") { state.chooseEngine(.offlineFirst) }.disabled(state.template.id != "translate")
                Button("AI 翻译") { state.chooseEngine(.ai) }
            } label: {
                HStack(spacing: Tokens.Space.xs) {
                    Text(state.engineLabel).font(Tokens.Typography.font(Tokens.Typography.caption)).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium))
                }.frame(height: TranslateWindowLayout.iconSide)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(p.secondary).tint(p.secondary)
                .help(state.engineLabel + "；临时切换翻译引擎，Apple 不可用时沿用配置回退")
            Spacer(minLength: Tokens.Space.sm)
            SpeakButton(speaker: state.translationSpeaker, text: state.result.answer, compact: true)
                .disabled(state.result.isBusy).accessibilityLabel(state.translationSpeaker.isActive ? "停止朗读译文" : "朗读译文")
            slots.replacement()
            Button { copy(true, false) } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(TranslateIconButtonStyle()).help("复制原文").accessibilityLabel("复制原文").disabled(state.original.isEmpty)
            Button("复制译文") { copy(false, false) }
                .buttonStyle(DesignButtonStyle(variant: .primary)).fixedSize().disabled(!state.result.canCopy)
                .help("复制译文 ⌘C；⌘↩ 复制并返回")
        }.padding(.horizontal, Tokens.Space.lg).padding(.vertical, Tokens.Space.sm)
    }
    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(Tokens.Typography.font(Tokens.Typography.caption, weight: .medium)).foregroundStyle(p.secondary)
    }
    private var languageBar: some View {
        HStack(spacing: 0) {
            Menu {
                Button("自动检测") { state.chooseSource("auto") }
                ForEach(TranslateWindowState.languages, id: \.id) { language in Button(language.title) { state.chooseSource(language.id) } }
            } label: { languageLabel(state.sourceLabel) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(maxWidth: .infinity)
                .help("原文语言；手动指定时使用 AI，Apple 使用自动检测")
            Button(action: state.swap) { Image(systemName: "arrow.left.arrow.right") }
                .buttonStyle(TranslateIconButtonStyle()).help("对调语言与已完成译文 ⌘L").accessibilityLabel("对调语言")
                .disabled(state.result.phase != .done)
            Menu {
                ForEach(TranslateWindowState.languages, id: \.id) { language in Button(language.title) { state.chooseTarget(language.id) } }
            } label: { languageLabel(TranslateWindowState.languageName(state.targetLanguage)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(maxWidth: .infinity)
                .help("目标语言，自动记住选择")
        }.foregroundStyle(p.secondary).tint(p.secondary)
            .padding(.horizontal, Tokens.Space.lg).padding(.vertical, Tokens.Space.xs)
            .frame(maxWidth: .infinity).background(p.canvas.opacity(0.5))
            .overlay(alignment: .top) { Rectangle().fill(p.borderSubtle).frame(height: Tokens.Size.hairline) }
            .overlay(alignment: .bottom) { Rectangle().fill(p.borderSubtle).frame(height: Tokens.Size.hairline) }
    }
    private func languageLabel(_ title: String) -> some View {
        HStack(spacing: Tokens.Space.xs) {
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium))
        }.font(Tokens.Typography.font(Tokens.Typography.meta, weight: .medium)).frame(maxWidth: .infinity)
    }
    private var placeholder: String {
        switch state.result.phase {
        case .connecting: "正在翻译…"
        case .thinking: "正在思考…"
        case .failed: "未能完成翻译"
        case .cancelled: "已停止翻译"
        default: "译文会显示在这里"
        }
    }
}
