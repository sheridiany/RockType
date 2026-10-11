import Foundation
import Observation
import RoarkTCore

/// One preview owns one translation stream. No global result window or history side effects.
@MainActor @Observable final class ScreenshotTranslation {
    enum Phase { case idle, running, done, failed, cancelled }
    private(set) var phase: Phase = .idle
    private(set) var text = ""
    private(set) var engine = ""
    private(set) var notice: String?
    @ObservationIgnored private let runner: any OperationRunner
    @ObservationIgnored private let allowed: () -> Bool
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(runner: any OperationRunner, allowed: @escaping () -> Bool) {
        self.runner = runner; self.allowed = allowed
    }
    func clear() {
        generation += 1; task?.cancel(); task = nil; runner.stop()
        text = ""; engine = ""; notice = nil; phase = .idle
    }
    func cancel() {
        guard phase == .running else { return }
        clear(); phase = .cancelled; notice = "翻译已取消，可以重新开始。"
    }
    func run(text source: String, settings: AppSettings) {
        clear()
        guard allowed() else { phase = .failed; notice = "安全输入已启用，翻译已停止。"; return }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let template = settings.templates.first(where: { $0.id == "translate" && $0.input == .text }) else {
            phase = .failed; notice = "翻译模板不可用，请在设置中恢复。"; return
        }
        let snapshot = ContentSnapshot(text: source, source: .init(pid: ProcessInfo.processInfo.processIdentifier,
            applicationName: "截图 OCR"), method: .screenshotOCR)
        let session = OperationSession(snapshot: snapshot)
        let request = OperationRequest(session: session, template: template, settings: settings)
        let current = generation
        phase = .running; runner.start()
        let events = runner.run(request)
        task = Task { [weak self] in
            for await event in events {
                guard let self, !Task.isCancelled, self.generation == current else { return }
                guard self.allowed() else {
                    self.clear(); self.phase = .failed; self.notice = "安全输入已启用，翻译已停止。"; return
                }
                switch event {
                case .started, .thinking: break
                case .engine(let value): self.engine = value
                case .delta(let value): self.text += value
                case .completed(let result):
                    guard result.session.id == session.id, result.session.snapshot == snapshot,
                          !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        self.fail("翻译结果不完整，请重试。"); return
                    }
                    self.text = result.text; self.engine = result.engine; self.phase = .done
                    self.task = nil; return
                case .failed(let failure):
                    self.fail(Self.message(failure)); return
                case .cancelled:
                    self.cancel(); return
                }
            }
            guard let self, !Task.isCancelled, self.generation == current, self.phase == .running else { return }
            self.fail("翻译连接已结束，但未收到完整结果。请重试。")
        }
    }
    private func fail(_ message: String) {
        clear(); phase = .failed; notice = message
    }
    private static func message(_ error: OperationFailure) -> String {
        switch error {
        case .protectedInput: "安全输入已启用，翻译已停止。"
        case .inputTooLong(let limit): "文字超过本次翻译上限（\(limit) 字节），请缩短后重试。"
        case .ai(.configuration): "请先在设置中配置翻译服务或 AI 连接。"
        case .ai(.unauthorized): "连接认证失败，请检查密钥和模型权限。"
        case .ai(.rateLimited): "服务请求过多，请稍后重试。"
        case .ai(.timeout): "翻译超时，请重试。"
        default: "翻译未完成，请检查连接后重试。"
        }
    }
    isolated deinit { task?.cancel(); runner.stop() }
}
