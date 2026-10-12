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

/// Phase-B integrations can supply a dictionary card and speech button without changing the layout.
struct TranslateWindowSlots {
    var dictionary: (String) -> AnyView = { _ in AnyView(EmptyView()) }
    var speech: (String) -> AnyView = { _ in AnyView(Image(systemName: "speaker.wave.2").foregroundStyle(.tertiary).help("朗读将在组件接入后可用")) }
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
    @FocusState private var questionFocused: Bool
    @Environment(\.colorScheme) private var scheme
    private var p: Tokens.Palette { Tokens.palette(scheme) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("翻译", systemImage: "character.bubble").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { state.followupExpanded.toggle(); if state.followupExpanded { focusEditor(); questionFocused = true } } label: { Label("追问", systemImage: "text.bubble").font(.system(size: 11)) }
                    .help("追问").accessibilityLabel("展开或收起追问").disabled(!state.result.canAsk)
                Button(action: state.submit) { Image(systemName: "arrow.clockwise") }.help("重新翻译 ⌘R").accessibilityLabel("重新翻译")
                Button(action: close) { Image(systemName: "xmark") }.help("关闭 Esc").accessibilityLabel("关闭翻译窗")
            }.buttonStyle(.plain).foregroundStyle(p.secondary).padding(16)
                .background(ResultWindowDragArea())
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("原文").font(.system(size: 11, weight: .medium)).foregroundStyle(p.secondary)
                            Spacer()
                            Button(state.expanded ? "收起" : "展开") { state.expanded.toggle() }
                                .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(p.secondary).help("展开或收起原文")
                        }
                        ZStack(alignment: .topLeading) {
                            if state.original.isEmpty { Text("输入要翻译的文字…").font(.system(size: 14)).foregroundStyle(p.tertiary).padding(.top, 4).allowsHitTesting(false) }
                            TranslateSourceEditor(text: state.original, expanded: state.expanded,
                                changed: { state.edit($0, composing: $1) }, submit: state.submit, focus: focusEditor)
                                .frame(height: state.expanded ? 168 : 72)
                        }
                    }
                    languageBar
                    slots.dictionary(state.dictionaryInput)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("译文").font(.system(size: 11, weight: .medium)).foregroundStyle(p.secondary)
                            Spacer()
                            if state.result.isBusy { ProgressView().controlSize(.mini) }
                            if state.result.isBusy { Button("停止") { state.result.cancel() }.font(.system(size: 11)).buttonStyle(.plain) }
                        }
                        if state.result.answer.isEmpty {
                            Text(placeholder).font(.system(size: 14)).foregroundStyle(p.tertiary)
                                .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                        } else {
                            ResultAnswerView(text: state.result.answer, markdown: true, copyCode: copyCode)
                                .font(.system(size: 15)).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if let notice = state.result.notice { Text(notice).font(.system(size: 11)).foregroundStyle(p.secondary).fixedSize(horizontal: false, vertical: true) }
                    if state.followupExpanded {
                        HStack(alignment: .bottom, spacing: 8) {
                            TextField("基于这段译文追问", text: Binding(get: { state.result.question }, set: { state.result.question = $0 }), axis: .vertical)
                                .textFieldStyle(.plain).lineLimit(1...4).focused($questionFocused).onSubmit { state.ask() }
                            Button { state.ask() } label: { Image(systemName: "arrow.up.circle.fill") }
                                .buttonStyle(.plain).help("发送追问").accessibilityLabel("发送追问")
                                .disabled(state.result.isBusy || state.result.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }.padding(12).background(p.canvas, in: RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(.horizontal, 16).padding(.bottom, 16)
            }
            Rectangle().fill(p.borderSubtle).frame(height: 0.5)
            HStack(spacing: 12) {
                Menu {
                    Button("Apple 优先") { state.chooseEngine(.offlineFirst) }.disabled(state.template.id != "translate")
                    Button("AI 翻译") { state.chooseEngine(.ai) }
                } label: { Text(state.engineLabel).font(.system(size: 10)).lineLimit(1).truncationMode(.middle) }
                    .menuStyle(.borderlessButton).help("临时切换翻译引擎；Apple 不可用时沿用配置回退")
                Spacer(minLength: 0)
                slots.speech(state.result.answer)
                slots.replacement()
                Button { copy(true, false) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain).help("复制原文").accessibilityLabel("复制原文").disabled(state.original.isEmpty)
                Button("复制译文") { copy(false, false) }
                    .buttonStyle(DesignButtonStyle(variant: .primary)).disabled(!state.result.canCopy).help("复制译文 ⌘C；⌘↩ 复制并返回")
            }.padding(12)
        }
        .foregroundStyle(p.textPrimary).background(p.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(p.borderSubtle, lineWidth: 0.5))
    }
    private var languageBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("自动检测") { state.chooseSource("auto") }
                ForEach(TranslateWindowState.languages, id: \.id) { language in Button(language.title) { state.chooseSource(language.id) } }
            } label: { Text(state.sourceLabel).font(.system(size: 12, weight: .medium)).lineLimit(1) }
                .menuStyle(.borderlessButton).help("原文语言；手动指定时使用 AI，Apple 使用自动检测")
            Button(action: state.swap) { Image(systemName: "arrow.left.arrow.right") }
                .buttonStyle(.plain).foregroundStyle(p.secondary).help("对调语言与已完成译文 ⌘L").accessibilityLabel("对调语言")
                .disabled(state.result.phase != .done)
            Menu {
                ForEach(TranslateWindowState.languages, id: \.id) { language in Button(language.title) { state.chooseTarget(language.id) } }
            } label: { Text(TranslateWindowState.languageName(state.targetLanguage)).font(.system(size: 12, weight: .medium)).lineLimit(1) }
                .menuStyle(.borderlessButton).help("目标语言，自动记住选择")
        }.padding(12).background(p.canvas, in: RoundedRectangle(cornerRadius: 8))
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
