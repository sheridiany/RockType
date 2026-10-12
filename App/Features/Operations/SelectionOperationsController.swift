import AppKit
import RoarkTCore
import RoarkTPlatform

/// Owns the toolbar → runner → live window → session-only history path.
@MainActor final class SelectionOperationsController {
    let environment: OperationsEnvironment
    private(set) var window: ResultWindowController?
    private(set) var windows: [ResultWindowController] = []
    private(set) var translationWindow: TranslateWindowController?
    var rememberTranslationTarget: (String) -> Void = { _ in }
    private let settings: @MainActor () -> AppSettings
    private let aiConfigured: @MainActor () -> Bool
    private let notice: @MainActor (String) -> Void
    private let readable: @MainActor () -> Bool
    private let makeRunner: @MainActor () -> any OperationRunner

    init(environment: OperationsEnvironment, settings: @escaping @MainActor () -> AppSettings,
         aiConfigured: @escaping @MainActor () -> Bool,
         notice: @escaping @MainActor (String) -> Void,
         readable: @escaping @MainActor () -> Bool = { SecureInput.status() == .allowed },
         makeRunner: (@MainActor () -> any OperationRunner)? = nil) {
        self.environment = environment; self.settings = settings
        self.aiConfigured = aiConfigured; self.notice = notice; self.readable = readable
        self.makeRunner = makeRunner ?? {
            environment.makeRunner(connectionID: settings().ai.id, currentConnectionID: { settings().ai.id })
        }
    }

    func perform(_ request: OperationRequest, source: OperationSource?, toolbarRect: CGRect?) {
        guard readable() else { notice("当前输入受保护或无法检查，未发送请求。"); return }
        var current = settings()
        guard aiConfigured() || request.template.id == "translate" && request.question == nil else {
            notice("请前往设置配置 AI 连接后使用此操作。"); return
        }
        if !aiConfigured() { current.translation.engine = .offlineFirst }
        let request = OperationRequest(session: request.session, template: request.template,
            settings: current, question: request.question, maximumInputBytes: request.maximumInputBytes)
        if TranslateWindowState.accepts(request.template) {
            showTranslation(request, source: source, anchor: toolbarRect)
        } else { replaceWindow()?.show(request, source: source, toolbarRect: toolbarRect) }
    }

    func presentCompleted(_ result: OperationResult, template: OperationTemplate) {
        guard readable() else { return }
        if settings().privacy.keepRecentResultsInMemory { environment.recent.add(result) }
        if TranslateWindowState.accepts(template) {
            let request = OperationRequest(session: result.session, template: template, settings: settings())
            showTranslation(request, source: nil, anchor: nil, completed: result)
            return
        }
        replaceWindow()?.show(result, template: template, initialRetryUnavailable:
            ScreenshotSession.imageTemplate(forID: result.templateID) != nil
                ? "追问仅基于文字解释。原图未保留在对话中；重新解释图片请从图片预览确认发送。" : nil)
    }

    func reopen(_ result: OperationResult) {
        guard readable() else { notice("当前输入受保护或无法检查，未打开结果。"); return }
        guard environment.recent.results.contains(where: { $0.id == result.id }) else { return }
        // A deleted custom template does not prevent reading/copying an existing result.
        let template = settings().templates.first { $0.id == result.templateID }
            ?? ScreenshotSession.imageTemplate(forID: result.templateID)
            ?? OperationTemplate(id: result.templateID, name: "最近结果", icon: "text.bubble", prompt: "")
        if TranslateWindowState.accepts(template) {
            let request = OperationRequest(session: result.session, template: template, settings: settings())
            showTranslation(request, source: nil, anchor: nil, completed: result)
            return
        }
        replaceWindow()?.show(result, template: template, initialRetryUnavailable:
            ScreenshotSession.imageTemplate(forID: result.templateID) != nil
                ? "追问仅基于文字解释。原图未保留在对话中；重新解释图片请从图片预览确认发送。" : nil)
    }

    func openInputTranslation(templateID: String = "translate") {
        guard readable() else { notice("当前输入受保护或无法检查，未打开翻译。 "); return }
        var current = settings()
        guard let template = current.templates.first(where: { $0.id == templateID }), TranslateWindowState.accepts(template) else { return }
        if !aiConfigured() { current.translation.engine = .offlineFirst }
        let snapshot = ContentSnapshot(text: "", source: .init(pid: ProcessInfo.processInfo.processIdentifier,
            bundleID: Identifiers.appBundleID, applicationName: "输入翻译"), method: .paste)
        showTranslation(.init(session: .init(snapshot: snapshot), template: template, settings: current), source: nil, anchor: nil, focus: true)
    }

    func showTranslation(_ request: OperationRequest, source: OperationSource?, anchor: CGRect?, focus: Bool = false, completed: OperationResult? = nil) {
        guard readable() else { return }
        translationWindow?.close()
        let controller = TranslateWindowController(request: request, runner: makeRunner(), settings: settings,
            rememberTarget: { [weak self] in self?.rememberTranslationTarget($0) }, allowed: readable,
            completed: { [weak self] result in
                guard let self, self.readable(), self.settings().privacy.keepRecentResultsInMemory else { return }
                self.environment.recent.add(result)
            }, feedback: notice)
        translationWindow = controller
        controller.show(source: source, anchor: anchor ?? request.session.snapshot.selectionRect, focus: focus, completed: completed)
    }

    func search(_ snapshot: ContentSnapshot, settings: AppSettings) {
        do {
            if try !environment.search(snapshot.text, settings: settings.selection) {
                notice("无法打开搜索，请检查默认浏览器与搜索设置。")
            }
        } catch { notice("无法搜索，请检查输入保护状态与搜索设置。") }
    }

    func settingsChanged() {
        if !settings().privacy.keepRecentResultsInMemory { environment.recent.clear() }
        windows.forEach { $0.applySettings() }
    }

    func clearCurrentContent() {
        translationWindow?.close(); translationWindow = nil
        windows.forEach { $0.stop() }; windows.removeAll(); window = nil
        environment.clearCurrentContent()
    }
    func stop() { clearCurrentContent() }

    private func replaceWindow() -> ResultWindowController? {
        windows.removeAll { controller in
            if !controller.isVisible { controller.stop(); return true }
            return false
        }
        if let window, !window.state.pinned {
            window.stop(); windows.removeAll { $0 === window }
        }
        guard windows.count < 4 else {
            notice("已有 4 个置顶结果窗口，请先关闭一个再开始新操作。")
            return nil
        }
        let controller = ResultWindowController(runner: makeRunner(), settings: settings, feedback: notice,
            completed: { [weak self] result in
                guard let self, self.readable(), self.settings().privacy.keepRecentResultsInMemory else { return }
                self.environment.recent.add(result)
            }, readable: readable, aiConfigured: aiConfigured)
        windows.append(controller)
        window = controller
        return controller
    }
}
