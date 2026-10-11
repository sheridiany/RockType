import AppKit
import RoarkTCore
import RoarkTPlatform

/// Owns the toolbar → runner → live window → session-only history path.
@MainActor final class SelectionOperationsController {
    let environment: OperationsEnvironment
    private(set) var window: ResultWindowController?
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
        replaceWindow().show(request, source: source, toolbarRect: toolbarRect)
    }

    func reopen(_ result: OperationResult) {
        guard readable() else { notice("当前输入受保护或无法检查，未打开结果。"); return }
        guard environment.recent.results.contains(where: { $0.id == result.id }) else { return }
        // A deleted custom template does not prevent reading/copying an existing result.
        let template = settings().templates.first { $0.id == result.templateID }
            ?? OperationTemplate(id: result.templateID, name: "最近结果", icon: "text.bubble", prompt: "")
        replaceWindow().show(result, template: template)
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
        window?.applySettings()
    }

    func clearCurrentContent() {
        window?.stop(); window = nil
        environment.clearCurrentContent()
    }
    func stop() { clearCurrentContent() }

    private func replaceWindow() -> ResultWindowController {
        window?.stop()
        let controller = ResultWindowController(runner: makeRunner(), settings: settings, feedback: notice,
            completed: { [weak self] result in
                guard let self, self.readable(), self.settings().privacy.keepRecentResultsInMemory else { return }
                self.environment.recent.add(result)
            }, readable: readable, aiConfigured: aiConfigured)
        window = controller
        return controller
    }
}
