#if DEBUG
import SwiftUI

struct ResultWindowView: View {
    @State private var model: ResultWindowModel
    @State private var sourceExpanded = false
    @State private var asking = false
    @State private var question = ""
    @State private var pinned = false
    @State private var feedback: String?
    @State private var closed = false
    @Environment(\.colorScheme) private var scheme
    let rendering: Bool
    @FocusState private var questionFocused: Bool

    init(model: ResultWindowModel, rendering: Bool = false) {
        _model = State(initialValue: model); self.rendering = rendering
    }
    private var status: ResultStatus {
        switch model.turns.last?.phase {
        case .connecting: .connecting
        case .streaming: .streaming
        case .incomplete: .incomplete
        case .cancelled: .cancelled
        case .error: .error
        default: .done
        }
    }
    private var height: CGFloat {
        [.longContent, .followup, .code].contains(model.state) || asking || sourceExpanded
            ? Tokens.Size.resultMaxHeight : Tokens.Size.resultMinHeight + Tokens.Size.row * (model.notice == nil ? 3 : 4)
    }
    var body: some View {
        let p = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            HStack(spacing: Tokens.Space.sm) {
                Image(systemName: model.action.symbol).foregroundStyle(p.secondary)
                Text(model.action.title).font(Tokens.Typography.font(weight: .medium))
                if let language = model.targetLanguage {
                    if rendering {
                        Text("英文 → " + language).foregroundStyle(p.secondary)
                    } else {
                        DesignSelect(title: "目标语言", selection: Binding(
                            get: { model.targetLanguage ?? language },
                            set: { model.targetLanguage = $0; feedback = "目标语言已切换，示例内容保持不变" }
                        ), options: ["中文", "英文", "日文", "法文"].map { DesignOption(title: $0, value: $0) })
                        .disabled(model.isBusy).fixedSize()
                    }
                }
                Spacer(minLength: 0)
                Button { pinned.toggle() } label: { Image(systemName: pinned ? "pin.fill" : "pin") }
                    .accessibilityLabel(pinned ? "取消置顶" : "置顶")
                Button { closed = true } label: { Image(systemName: "xmark") }.accessibilityLabel("关闭")
            }.buttonStyle(DesignButtonStyle(variant: .ghost))
            Rectangle().fill(p.line).frame(height: Tokens.Size.hairline)
            if closed {
                Notice(text: "结果浮窗已关闭", actionTitle: "重新打开", action: { closed = false })
                Spacer()
            } else {
                Group {
                    if rendering {
                        GeometryReader { viewport in
                            resultContent.frame(width: viewport.size.width)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
                                .clipped()
                        }
                    } else {
                        ScrollView { resultContent }
                    }
                }
                if asking {
                    HStack(spacing: Tokens.Space.sm) {
                        DesignTextField(title: "继续追问", text: $question)
                            .focused($questionFocused).onSubmit(ask)
                        Button("发送", action: ask).disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
                            .buttonStyle(DesignButtonStyle(variant: .secondary))
                    }
                }
                HStack {
                    Button(sourceExpanded ? "收起原文" : "原文") { sourceExpanded.toggle() }
                        .accessibilityValue(sourceExpanded ? "已展开" : "已折叠")
                    Text(model.captureMethod).font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.tertiary)
                    Spacer(minLength: 0)
                    if model.action != .translate && model.hasAnswer {
                        Button("追问") { asking = true; questionFocused = true }.keyboardShortcut("l")
                    }
                    if model.recovery == nil && status != .error {
                        Button("重试", action: retry).disabled(model.isBusy)
                    }
                }.buttonStyle(DesignButtonStyle(variant: .ghost))
                StatusLine(status: status, detail: model.model + " · " + model.elapsed)
                HStack(spacing: Tokens.Space.sm) {
                    Button("复制") { feedback = "结果已复制" }.keyboardShortcut("c")
                        .buttonStyle(DesignButtonStyle(variant: .ghost)).disabled(!model.hasAnswer)
                    Kbd("⌘C")
                    Spacer(minLength: 0)
                    if model.isBusy {
                        Button("停止", action: stop).keyboardShortcut(.cancelAction)
                            .buttonStyle(DesignButtonStyle(variant: .primary))
                        Kbd("Esc")
                    } else {
                        Button(model.sourceAvailable ? "复制并返回" : "仅复制") {
                            feedback = model.sourceAvailable ? "结果已复制，已返回模拟来源" : "结果已复制；来源窗口已关闭"
                        }.keyboardShortcut(.return, modifiers: .command)
                            .buttonStyle(DesignButtonStyle(variant: .primary)).disabled(!model.hasAnswer)
                        Kbd("⌘↩")
                    }
                }
            }
        }
        .padding(Tokens.Space.lg).frame(width: Tokens.Size.resultWidth, height: height)
        .modifier(DesignSurface())
        .onExitCommand { if model.isBusy { stop() } else if asking { asking = false } else { closed = true } }
        .accessibilityLabel("结果浮窗 · " + model.state.title)
    }
    private var resultContent: some View {
        let p = Tokens.palette(scheme)
        return VStack(alignment: .leading, spacing: Tokens.Space.md) {
            ForEach(model.turns) { turn in
                if let question = turn.question {
                    Text(question).padding(Tokens.Space.sm)
                        .background(p.askBubble, in: RoundedRectangle(cornerRadius: Tokens.Radius.bubble))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if turn.phase == .connecting {
                    Label("正在连接…", systemImage: "ellipsis.circle")
                        .foregroundStyle(p.secondary).padding(.vertical, Tokens.Space.md)
                }
                if !turn.answer.isEmpty {
                    Text(turn.answer + (turn.phase == .streaming ? " ▍" : ""))
                        .font(Tokens.Typography.font(Tokens.Typography.read))
                        .lineSpacing(Tokens.Typography.readingSpacing)
                        .foregroundStyle(turn.phase == .incomplete || turn.phase == .cancelled ? p.secondary : p.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let code = turn.code {
                    Text(code).font(.system(size: Tokens.Typography.meta, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Tokens.Space.md)
                        .background(p.cardSecondary, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
                }
            }
            if let notice = model.notice {
                Notice(text: notice, tone: status == .error ? .danger : .warn)
                if let recovery = model.recovery {
                    Button(recovery) {
                        if recovery == "重试" { retry() } else { feedback = recovery + "入口已选中" }
                    }.buttonStyle(DesignButtonStyle(variant: .secondary))
                }
            }
            if let feedback { Notice(text: feedback, tone: .ok) }
            if sourceExpanded {
                VStack(alignment: .leading, spacing: Tokens.Space.sm) {
                    Text(model.sourceApp + " · " + model.captureMethod)
                        .font(Tokens.Typography.font(Tokens.Typography.caption)).foregroundStyle(p.secondary)
                    Text(model.original).font(Tokens.Typography.font(Tokens.Typography.meta))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("复制原文") { feedback = "原文已复制" }
                        .buttonStyle(DesignButtonStyle(variant: .ghost))
                }.padding(Tokens.Space.md)
                    .background(p.bubble, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func stop() {
        guard let index = model.turns.indices.last, model.isBusy else { return }
        model.turns[index].phase = .cancelled
        model.notice = "已停止，保留已生成的部分结果。"; model.recovery = nil
    }
    private func retry() {
        let answer: String
        switch model.action {
        case .summarize: answer = SurfaceSampleText.summary
        case .explain: answer = "取消会向任务发出信号；任务应检查取消状态，停止更新结果。"
        default: answer = SurfaceSampleText.translation
        }
        model.turns = [.init(id: "retry", answer: answer, phase: .done)]
        model.notice = nil; model.recovery = nil; model.state = .done
        feedback = "已重新生成示例结果"
    }
    private func ask() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !model.isBusy else { return }
        model.turns.append(.init(id: "followup-\(model.turns.count)", question: text,
                                answer: SurfaceSampleText.answer, phase: .done))
        question = ""; model.notice = nil; feedback = nil
    }
}

#endif
