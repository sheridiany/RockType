import Foundation
import Observation
import RoarkTCore

/// Runtime-only presentation state. The runner is dedicated to this window.
@MainActor @Observable
final class ResultWindowState {
    enum Phase { case idle, connecting, streaming, done, cancelled, failed }
    private(set) var phase: Phase = .idle
    private(set) var request: OperationRequest?
    private(set) var session: OperationSession?
    private(set) var answer = ""
    private(set) var engine = ""
    private(set) var history: [OperationTurn] = []
    private(set) var currentQuestion: String?
    var notice: String?
    var asking = false
    var question = ""
    var pinned = false
    var sourceExpanded = false
    var isBusy: Bool { phase == .connecting || phase == .streaming }
    var canCopy: Bool { !answer.isEmpty }
    @ObservationIgnored private let runner: any OperationRunner
    @ObservationIgnored private let readable: @MainActor () -> Bool
    @ObservationIgnored private let completed: @MainActor (OperationResult) -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var revision: UInt64 = 0

    init(runner: any OperationRunner, readable: @escaping @MainActor () -> Bool,
         completed: @escaping @MainActor (OperationResult) -> Void = { _ in }) {
        self.runner = runner; self.readable = readable; self.completed = completed
    }

    func start() { runner.start() }
    func stop() { clear(); runner.stop() }

    func show(_ request: OperationRequest) {
        cancel()
        self.request = request; session = request.session
        asking = false; question = ""; sourceExpanded = false
        pinned = request.settings.selection.automaticallyPin
        execute(request)
    }

    func show(_ result: OperationResult, template: OperationTemplate, settings: AppSettings) {
        cancel()
        let previous = OperationSession(id: result.session.id, snapshot: result.session.snapshot,
                                        turns: Array(result.session.turns.dropLast()))
        let lastQuestion = result.session.turns.last?.question
        request = OperationRequest(session: previous, template: template, settings: settings,
                                   question: lastQuestion?.isEmpty == false ? lastQuestion : nil)
        session = result.session; answer = result.text; engine = result.engine
        history = Array(result.session.turns.dropLast()); currentQuestion = result.session.turns.last?.question
        phase = .done; notice = nil
        asking = false; question = ""; sourceExpanded = false
        pinned = settings.selection.automaticallyPin
    }

    func ask(settings: AppSettings) {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, !text.isEmpty, let request, let session else { return }
        let template = settings.templates.first { $0.id == request.template.id } ?? request.template
        execute(OperationRequest(session: session, template: template, settings: settings,
                                 question: text, maximumInputBytes: request.maximumInputBytes))
        question = ""
    }

    func retry(settings: AppSettings) {
        guard !isBusy, let request else { return }
        let template = settings.templates.first { $0.id == request.template.id } ?? request.template
        execute(OperationRequest(session: request.session, template: template, settings: settings,
                                 question: request.question, maximumInputBytes: request.maximumInputBytes))
    }

    func cancel() {
        revision &+= 1
        task?.cancel(); task = nil; runner.cancel()
        if isBusy { phase = .cancelled; notice = "已停止，保留已生成的部分结果。" }
    }

    func clear() {
        cancel(); request = nil; session = nil; answer = ""; engine = ""
        currentQuestion = nil; history = []; question = ""; asking = false; notice = nil; phase = .idle
    }

    private func execute(_ request: OperationRequest) {
        cancel()
        self.request = request; currentQuestion = request.question; history = request.session.turns
        answer = ""; engine = ""; notice = nil
        guard readable() else { phase = .failed; notice = "当前输入受保护或无法检查，未发送请求。"; return }
        phase = .connecting
        let revision = self.revision
        let stream = runner.run(request)
        task = Task { [weak self] in
            for await event in stream {
                guard let self, !Task.isCancelled, self.revision == revision else { return }
                guard self.readable() else {
                    self.cancel(); self.answer = ""; self.phase = .failed
                    self.notice = "当前输入受保护或无法检查，已停止请求。"
                    return
                }
                switch event {
                case .started: break
                case .engine(let engine): self.engine = engine
                case .delta(let delta): self.answer += delta; self.phase = .streaming
                case .completed(let result):
                    guard result.session.id == request.session.id,
                          result.session.snapshot == request.session.snapshot,
                          result.templateID == request.template.id else {
                        self.phase = .failed; self.notice = "结果与当前操作不匹配，请重试。"; return
                    }
                    self.answer = result.text; self.engine = result.engine
                    self.session = result.session; self.phase = .done
                    self.completed(result)
                    return
                case .failed(let failure):
                    self.phase = .failed; self.notice = Self.message(failure); return
                case .cancelled:
                    self.phase = .cancelled; self.notice = "已停止，保留已生成的部分结果。"; return
                }
            }
            guard let self, !Task.isCancelled, self.revision == revision, self.isBusy else { return }
            self.phase = .failed; self.notice = "连接已结束，结果不完整，请重试。"
        }
    }

    private static func message(_ error: OperationFailure) -> String {
        switch error {
        case .emptyInput: "没有可处理的内容。"
        case .inputTooLong(let limit): "内容超过模型输入上限（\(limit) 字节），请缩短后重试。"
        case .unsupportedInput: "当前模型不支持此类输入，请检查模型配置。"
        case .protectedInput: "当前输入受保护，已停止请求。"
        case .unavailable: "服务暂不可用，请检查连接后重试。"
        case .invalidSearchURL: "搜索地址无效，请检查设置。"
        case .ai(let error):
            switch error {
            case .configuration: "请先在设置中配置 AI 连接。"
            case .unauthorized: "认证失败，请检查密钥与模型权限。"
            case .modelNotFound: "模型不可用，请检查模型名称与权限。"
            case .rateLimited: "请求过于频繁，请稍后重试。"
            case .timeout: "请求超时，请重试。"
            case .cancelled: "请求已取消。"
            case .responseTooLarge: "响应过长，已停止接收。"
            case .decoding: "响应格式无法识别，请检查服务兼容性。"
            case .network, .server, .http: "连接失败，请检查网络和服务后重试。"
            }
        }
    }
}
