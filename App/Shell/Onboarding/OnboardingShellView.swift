import SwiftUI
import Translation

/// Live shell counterpart of U4. Uses its design tokens and cards; Gallery remains pure mock data.
struct OnboardingShellView: View {
    let flow: OnboardingFlow
    let input: InputSourceManager
    let language: LanguagePackModel
    let permissions: () -> AnyView
    let aiConnection: () -> AnyView
    let onFinish: () -> Void
    @State private var trial = ""
    @State private var busy = false
    @State private var inputTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Tokens.palette(scheme)
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            HStack {
                Text("欢迎使用 RockType").font(Tokens.Typography.font(Tokens.Typography.input, weight: .semibold))
                Spacer()
                Text("\((OnboardingStep.allCases.firstIndex(of: flow.step) ?? 0) + 1) / 5")
                    .monospacedDigit().foregroundStyle(palette.secondary)
            }
            HStack(spacing: Tokens.Space.sm) {
                ForEach(OnboardingStep.allCases) { step in
                    Button { flow.select(step) } label: {
                        Label(step.title, systemImage: step.symbol)
                            .frame(maxWidth: .infinity, minHeight: Tokens.Size.row)
                            .foregroundStyle(flow.step == step ? palette.accent : palette.secondary)
                            .background(flow.step == step ? palette.accentSoft : palette.card,
                                        in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(step == flow.step ? .isSelected : [])
                }
            }
            HStack {
                Text(flow.step.headline).font(Tokens.Typography.font(Tokens.Typography.input, weight: .semibold))
                Spacer()
                if let resolution = flow.resolutions[flow.step] {
                    Chip(text: resolution == .skipped ? "已跳过" : "已完成此步")
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.lg) {
                    Text(flow.step.explanation).foregroundStyle(palette.secondary)
                    U4Card { content }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = flow.errorMessage { Notice(text: error, tone: .danger) }
            U4Rule()
            HStack {
                Button("跳过此步") { flow.resolve(.skipped) }.buttonStyle(DesignButtonStyle(variant: .ghost))
                Text("以后可在设置中继续").font(Tokens.Typography.font(Tokens.Typography.caption))
                    .foregroundStyle(palette.secondary)
                Spacer()
                if flow.step != .voice {
                    Button(flow.step == .ai ? "开始使用" : "继续") { flow.resolve(.completed) }
                        .buttonStyle(DesignButtonStyle(variant: .primary)).disabled(!canContinue)
                }
            }
        }
        .padding(Tokens.Space.xxl)
        .frame(width: Tokens.Size.settingsWidth, height: Tokens.Size.settingsHeight)
        .font(Tokens.Typography.font()).foregroundStyle(palette.foreground).background(palette.background)
        .onChange(of: flow.step) { _, _ in cancelInput(); trial = "" }
        .onChange(of: flow.finished) { _, finished in if finished { onFinish() } }
        .onDisappear { cancelInput(); trial = "" }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in input.refresh() }
        .task(id: flow.step) {
            guard flow.step == .input else { return }
            await input.prepareRegistration()
            // Only reads input-source metadata, only while this window is visible.
            while !Task.isCancelled {
                input.refresh()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    private var canContinue: Bool {
        switch flow.step {
        case .input: input.verified
        case .language: language.canContinue
        case .permissions, .ai: true // User acknowledges this optional step; never implies permission/test success.
        case .voice: false
        }
    }

    @ViewBuilder private var content: some View {
        switch flow.step {
        case .input:
            Text("系统设置 → 键盘 → 输入法 → 编辑… → ＋ → 简体中文 → RockType")
                .font(Tokens.Typography.font(Tokens.Typography.meta))
            HStack {
                Chip(text: input.snapshot.addedIDs.isEmpty ? "尚未添加" : "已添加", tone: input.snapshot.addedIDs.isEmpty ? .warn : .ok)
                Chip(text: input.snapshot.selectedRoarkTID == nil ? "尚未选中" : "已选中",
                     tone: input.snapshot.selectedRoarkTID == nil ? .warn : .ok)
                Spacer()
                Button("打开键盘设置") { Task { await input.openKeyboardSettings() } }
                    .disabled(input.isRegistering || input.isOpeningSettings).buttonStyle(DesignButtonStyle())
            }
            if let message = input.registrationMessage { Notice(text: message) }
            Notice(text: input.message, tone: input.verified ? .ok : .neutral)
            TextField("开始验证后，在这里试打 nihao 并选字", text: $trial)
                .textFieldStyle(.roundedBorder).accessibilityLabel("输入法试打")
                .disabled(!input.isVerifying || busy)
            HStack {
                Button("开始试打验证") { runInput { await input.beginVerification() } }
                    .disabled(busy).buttonStyle(DesignButtonStyle())
                Button("验证试打") { runInput { await input.verify() } }
                    .disabled(busy || !input.isVerifying).buttonStyle(DesignButtonStyle(variant: .primary))
            }
        case .language:
            LanguagePackStepView(model: language)
        case .permissions:
            permissions()
            Text("按需选择权限；继续不会自动请求任何权限。")
                .font(Tokens.Typography.font(Tokens.Typography.caption))
        case .voice:
            Label("本地语音模型 · 即将推出", systemImage: "waveform")
            Text("语音模型下载将在后续版本提供。本阶段不会下载模型或开启麦克风，请跳过此步。")
        case .ai:
            aiConnection()
            Text("可不配置 AI 直接开始使用；连接是否可用以各项测试结果为准。")
                .font(Tokens.Typography.font(Tokens.Typography.caption))
        }
    }

    private func runInput(_ action: @escaping @MainActor () async -> Void) {
        busy = true
        inputTask = Task { @MainActor in
            await action()
            if !Task.isCancelled { busy = false }
        }
    }

    private func cancelInput() {
        inputTask?.cancel()
        inputTask = nil
        busy = false
        input.cancel()
    }
}

struct LanguagePackStepView: View {
    let model: LanguagePackModel
    @State private var preparing = false
    @State private var direction = 0
    var body: some View {
        Label("简体中文 ↔ English", systemImage: "arrow.left.arrow.right")
        Notice(text: model.state.message, tone: model.state == .installed ? .ok : .neutral)
        HStack {
            Button("重新检查") { Task { await model.refresh() } }
                .disabled(preparing || model.state == .checking).buttonStyle(DesignButtonStyle())
            if #available(macOS 26, *), model.state == .available || model.state == .failed {
                Button("准备语言包") { direction = 0; preparing = true }
                    .disabled(preparing).buttonStyle(DesignButtonStyle(variant: .primary))
            }
            if preparing {
                Button("取消") { preparing = false; model.preparationFailed() }.buttonStyle(DesignButtonStyle())
            }
        }
        if #available(macOS 26, *), preparing {
            LanguagePackPreparation(direction: direction) { success in
                guard preparing else { return }
                if success && direction == 0 { direction = 1 }
                else {
                    preparing = false
                    if success { await model.refresh() } else { model.preparationFailed() }
                }
            }.id(direction)
        }
        Text("只有点击准备后才请求系统下载；不会发送试打内容。")
            .font(Tokens.Typography.font(Tokens.Typography.caption))
            .task { await model.refresh() }
    }
}

@available(macOS 26, *)
private struct LanguagePackPreparation: View {
    let direction: Int
    let completed: @MainActor (Bool) async -> Void
    var body: some View {
        Text("正在准备\(direction == 0 ? "中译英" : "英译中")语言包…")
            .translationTask(source: .init(identifier: direction == 0 ? "zh-Hans" : "en"),
                             target: .init(identifier: direction == 0 ? "en" : "zh-Hans")) { @Sendable session in
                do {
                    try await session.prepareTranslation()
                    guard !Task.isCancelled else { return }
                    await completed(true)
                } catch {
                    guard !Task.isCancelled else { return }
                    await completed(false)
                }
            }
    }
}
