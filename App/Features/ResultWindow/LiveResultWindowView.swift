import SwiftUI
import RoarkTCore

/// Live surface shares D0 tokens and controls; gallery fixtures stay independent.
struct LiveResultWindowView: View {
    let controller: ResultWindowController
    @Environment(\.colorScheme) private var scheme
    @FocusState private var questionFocused: Bool

    var body: some View {
        @Bindable var state = controller.state
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            HStack {
                Label(state.request?.template.name ?? "结果", systemImage: state.request?.template.icon ?? "text.bubble")
                    .font(Tokens.Typography.font(weight: .medium))
                Spacer()
                Button(action: controller.setPinned) { Image(systemName: state.pinned ? "pin.fill" : "pin") }
                    .accessibilityLabel(state.pinned ? "取消置顶" : "置顶")
                Button(action: controller.close) { Image(systemName: "xmark") }.accessibilityLabel("关闭")
            }.buttonStyle(DesignButtonStyle(variant: .ghost))
            Rectangle().fill(p.line).frame(height: Tokens.Size.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.md) {
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
                    if !state.answer.isEmpty { answerText(state.answer + (state.phase == .streaming ? " ▍" : "")) }
                    if let notice = state.notice { Notice(text: notice, tone: state.phase == .failed ? .danger : .warn) }
                    if state.sourceExpanded, let snapshot = state.session?.snapshot {
                        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
                            Text(snapshot.source.applicationName).foregroundStyle(p.secondary)
                            answerText(snapshot.text)
                            Button("复制原文") { controller.copy(original: true) }
                                .buttonStyle(DesignButtonStyle(variant: .ghost))
                        }.padding(Tokens.Space.md)
                            .background(p.bubble, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if state.asking {
                HStack {
                    DesignTextField(title: "继续追问", text: $state.question)
                        .focused($questionFocused).onSubmit(controller.ask)
                    Button("发送", action: controller.ask)
                        .disabled(state.isBusy || state.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .buttonStyle(DesignButtonStyle(variant: .secondary))
                }
            }
            HStack {
                Button(state.sourceExpanded ? "收起原文" : "原文") { state.sourceExpanded.toggle() }
                    .accessibilityValue(state.sourceExpanded ? "已展开" : "已折叠")
                Text(captureMethod).font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.tertiary)
                Spacer()
                Button("追问") { controller.beginQuestion(); questionFocused = true }.disabled(!state.canAsk)
                Button("重试", action: controller.retry).disabled(state.isBusy)
            }.buttonStyle(DesignButtonStyle(variant: .ghost))
            HStack {
                Text(statusText)
                if !state.engine.isEmpty { Text(state.engine).lineLimit(1).help(state.engine) }
                Spacer()
            }.font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
                .accessibilityElement(children: .combine)
            HStack {
                Button("复制") { controller.copy() }.disabled(!state.canCopy)
                    .buttonStyle(DesignButtonStyle(variant: .ghost))
                Spacer()
                if state.isBusy {
                    Button("停止", action: state.cancel).buttonStyle(DesignButtonStyle(variant: .primary))
                    Kbd("Esc")
                } else {
                    Button("复制并返回") { controller.copy(returning: true) }.disabled(!state.canCopy)
                        .buttonStyle(DesignButtonStyle(variant: .primary))
                    Kbd("⌘↩")
                }
            }
        }.padding(Tokens.Space.lg).frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(DesignSurface())
            .onChange(of: state.asking) { _, asking in questionFocused = asking }
            .accessibilityLabel("结果浮窗")
    }

    private func answerText(_ text: String) -> some View {
        // Verbatim display preserves paragraphs, lists and code indentation while streaming.
        Text(text).font(Tokens.Typography.font(Tokens.Typography.read))
            .textSelection(.enabled)
            .lineSpacing(Tokens.Typography.readingSpacing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func questionBubble(_ text: String) -> some View {
        Text(text).padding(Tokens.Space.sm)
            .background(Tokens.palette(scheme).askBubble, in: RoundedRectangle(cornerRadius: Tokens.Radius.bubble))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
    private var captureMethod: String {
        if let id = controller.state.request?.template.id, let template = ScreenshotSession.imageTemplate(forID: id) { return template.name }
        return switch controller.state.session?.snapshot.method {
        case .accessibility: "直接读取"
        case .copyFallback: "复制回退"
        case .paste: "粘贴"
        case .screenshotOCR: "截图 OCR"
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
