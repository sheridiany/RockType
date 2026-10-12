import SwiftUI
import RoarkTCore

/// Live surface shares D0 tokens and controls; gallery fixtures stay independent.
struct LiveResultWindowView: View {
    let controller: ResultWindowController
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var questionFocused: Bool
    @State private var following = true
    @State private var jump = 0

    var body: some View {
        @Bindable var state = controller.state
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            HStack {
                HStack {
                    Label(state.request?.template.name ?? "结果", systemImage: state.request?.template.icon ?? "text.bubble")
                        .font(Tokens.Typography.font(weight: .medium)).lineLimit(1)
                    Spacer()
                }.overlay(ResultWindowDragArea().accessibilityHidden(true))
                Button(action: controller.setPinned) { Image(systemName: state.pinned ? "pin.fill" : "pin") }
                    .buttonStyle(ResultActionIconStyle(height: Tokens.Space.xxl))
                    .accessibilityLabel(state.pinned ? "取消置顶" : "置顶").help(state.pinned ? "取消置顶" : "置顶")
                Button(action: controller.close) { Image(systemName: "xmark") }
                    .buttonStyle(ResultActionIconStyle(height: Tokens.Space.xxl)).accessibilityLabel("关闭").help("关闭 · Esc")
            }.buttonStyle(DesignButtonStyle(variant: .ghost))
            Rectangle().fill(p.line).frame(height: Tokens.Size.hairline)
            ResultFollowingScrollView(resetID: state.session?.id, jump: jump, following: $following) {
                VStack(alignment: .leading, spacing: Tokens.Space.lg) {
                    if let snapshot = state.session?.snapshot {
                        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
                            Button { state.sourceExpanded.toggle() } label: {
                                HStack(spacing: Tokens.Space.sm) {
                                    Image(systemName: state.sourceExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 10, weight: .medium)).frame(width: 12)
                                    Text("原文").font(Tokens.Typography.font(Tokens.Typography.caption, weight: .medium))
                                    Text(snapshot.source.applicationName).lineLimit(1)
                                    Spacer(minLength: 0)
                                }.foregroundStyle(p.secondary).contentShape(Rectangle())
                            }.buttonStyle(.plain).help(state.sourceExpanded ? "收起原文" : "展开原文")
                                .accessibilityValue(state.sourceExpanded ? "已展开" : "已折叠")
                            if state.sourceExpanded {
                                ResultAnswerView(text: snapshot.text, markdown: false, copyCode: controller.copyCode)
                                    .padding(.leading, Tokens.Space.md)
                                    .overlay(alignment: .leading) { Rectangle().fill(p.line).frame(width: 2) }
                            }
                        }.font(Tokens.Typography.font(Tokens.Typography.caption))
                    }
                    ForEach(Array(state.history.enumerated()), id: \.offset) { _, turn in
                        if !turn.question.isEmpty { questionBubble(turn.question) }
                        answerText(turn.answer)
                    }
                    if let question = state.currentQuestion, !question.isEmpty { questionBubble(question) }
                    if state.phase == .connecting {
                        Label("正在连接…", systemImage: "ellipsis.circle").foregroundStyle(p.secondary)
                    }
                    if state.phase == .thinking {
                        Label("思考中…", systemImage: "sparkles").foregroundStyle(p.secondary)
                    }
                    if !state.answer.isEmpty { answerText(state.answer) }
                    if state.phase == .streaming {
                        Text("生成中…").font(.caption).foregroundStyle(p.secondary)
                    }
                    if let notice = state.notice { Notice(text: notice, tone: state.phase == .failed ? .danger : .warn) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if !following {
                HStack { Spacer(); Button("回到最新内容 ↓") { jump += 1 } }
                    .buttonStyle(DesignButtonStyle(variant: .ghost))
            }
            if state.asking {
                HStack(alignment: .bottom) {
                    TextEditor(text: $state.question)
                        .font(Tokens.Typography.font())
                        .scrollContentBackground(.hidden)
                        .padding(Tokens.Space.sm).frame(height: 64)
                        .background(p.bubble, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                        .overlay(alignment: .topLeading) {
                            if state.question.isEmpty {
                                Text("继续追问 · ⌘↩ 发送，↩ 换行").font(.caption).foregroundStyle(p.tertiary)
                                    .padding(12).allowsHitTesting(false)
                            }
                        }
                        .accessibilityLabel("继续追问，Command Return 发送，Return 换行")
                        .focused($questionFocused)
                    Button("发送", action: controller.ask).help("发送追问 · ⌘↩")
                        .disabled(state.isBusy || state.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .buttonStyle(DesignButtonStyle(variant: .secondary))
                }
            }
            Rectangle().fill(p.line).frame(height: Tokens.Size.hairline)
            HStack(spacing: Tokens.Space.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                    if !state.engine.isEmpty { Text(state.engine) }
                }.font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .help([statusText, state.engine, captureMethod].filter { !$0.isEmpty }.joined(separator: " · "))
                    .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                Menu {
                    Button("复制原文", systemImage: "doc.on.doc") { controller.copy(original: true) }
                        .disabled(state.session == nil)
                    Button("重试", systemImage: "arrow.clockwise", action: controller.retry)
                        .keyboardShortcut("r", modifiers: .command).disabled(state.isBusy || state.request == nil)
                    Divider()
                    Text(captureMethod)
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 28) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(p.secondary)
                    .help("更多操作").accessibilityLabel("更多操作")
                Button {
                    if state.asking { controller.escape() }
                    else { controller.beginQuestion() }
                } label: { Image(systemName: state.asking ? "bubble.left.fill" : "bubble.left") }
                    .buttonStyle(ResultActionIconStyle())
                    .disabled(state.asking ? state.isBusy : !state.canAsk)
                    .help(state.asking && state.isBusy ? "停止或完成生成后可收起追问" : (state.asking ? "收起追问" : "追问 · ⌘L"))
                    .accessibilityLabel(state.asking ? "收起追问" : "追问")
                if let replacement = controller.sourceReplacement {
                    SourceReplacementButton(replacement: replacement, text: state.answer,
                        enabled: state.phase == .done && state.currentQuestion == nil,
                        feedback: { state.notice = $0 })
                }
                Button { controller.copy() } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(ResultActionIconStyle())
                    .disabled(!state.canCopy).help("复制结果 · ⌘C").accessibilityLabel("复制结果")
                if state.isBusy {
                    Button("停止", action: state.cancel).buttonStyle(DesignButtonStyle(variant: .primary))
                        .help("停止生成 · Esc")
                } else {
                    Button("复制并返回") { controller.copy(returning: true) }.disabled(!state.canCopy)
                        .buttonStyle(DesignButtonStyle(variant: .primary)).layoutPriority(1).help("复制并返回来源 · ⌘↩")
                }
            }.buttonStyle(DesignButtonStyle(variant: .ghost)).lineLimit(1).fixedSize(horizontal: false, vertical: true)
        }.padding(Tokens.Space.lg).frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(DesignSurface())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: state.asking)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: state.sourceExpanded)
            .onChange(of: state.currentQuestion) { _, _ in jump += 1 }
            .onChange(of: state.asking) { _, asking in questionFocused = asking }
            .accessibilityLabel("结果浮窗")
    }

    private func answerText(_ text: String) -> some View {
        ResultAnswerView(text: text, markdown: controller.state.request?.template.output != .text,
                         copyCode: controller.copyCode)
    }
    private func questionBubble(_ text: String) -> some View {
        Text(text).padding(Tokens.Space.sm)
            .background(Tokens.palette(scheme).askBubble, in: RoundedRectangle(cornerRadius: Tokens.Radius.bubble))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
    private var captureMethod: String {
        if let template = controller.state.request?.template, ScreenshotSession.imageTemplate(forID: template.id) != nil { return template.name }
        return switch controller.state.session?.snapshot.method {
        case .accessibility: "直接读取"
        case .copyFallback: "复制回退"
        case .paste: "粘贴"
        case .screenshotOCR: "截图文字识别"
        case nil: ""
        }
    }
    private var statusText: String {
        switch controller.state.phase {
        case .idle: "等待操作"
        case .connecting: "连接中"
        case .thinking: "思考中"
        case .streaming: "生成中"
        case .done: "已完成"
        case .cancelled: "已停止"
        case .failed: "未完成"
        }
    }
}

private struct ResultActionIconStyle: ButtonStyle {
    var height: CGFloat = 32
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        let p = Tokens.palette(scheme)
        configuration.label.frame(width: 32, height: height)
            .foregroundStyle(enabled ? p.secondary : p.tertiary)
            .background(enabled && (hovering || configuration.isPressed) ? p.hover : .clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.control).stroke(focused ? p.focus : .clear, lineWidth: 2))
            .contentShape(Rectangle()).onHover { hovering = $0 }
    }
}
