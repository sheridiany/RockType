import AppKit
import Observation
import RoarkTCore
import RoarkTPlatform

/// One logical translation request for the entire image; the existing runner chooses the transport.
@MainActor @Observable final class ScreenshotOverlayTranslation {
    enum Phase { case idle, running, done, failed, cancelled }
    private(set) var phase: Phase = .idle
    private(set) var image: CGImage?
    private(set) var notice: String?
    private(set) var engine = ""
    private(set) var thinking = false
    @ObservationIgnored private let runner: any OperationRunner
    @ObservationIgnored private let allowed: () -> Bool
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    init(runner: any OperationRunner, allowed: @escaping () -> Bool) { self.runner = runner; self.allowed = allowed }
    func clear() {
        generation += 1; task?.cancel(); task = nil; runner.stop()
        image = nil; notice = nil; engine = ""; thinking = false; phase = .idle
    }
    func cancel() {
        guard phase == .running else { return }
        clear(); phase = .cancelled; notice = "覆盖式图片翻译已取消。"
    }
    nonisolated static func batchText(_ lines: [OCR.Line]) -> String {
        lines.enumerated().map { "[[RT:\($0.offset)]]\n\($0.element.text)" }.joined(separator: "\n") + "\n[[RT:END]]"
    }
    nonisolated static func parse(_ text: String, count: Int) throws -> [String] {
        guard text.utf8.count <= 65_536 else { throw OperationFailure.inputTooLong(limit: 65_536) }
        let regex = try NSRegularExpression(pattern: #"\[\[RT:(\d+)\]\]"#)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("[[RT:END]]") else { throw OperationFailure.unavailable }
        let ns = String(trimmed.dropLast("[[RT:END]]".count)) as NSString
        let matches = regex.matches(in: ns as String, range: NSRange(location: 0, length: ns.length))
        guard count > 0, matches.count == count, let first = matches.first,
              ns.substring(to: first.range.location).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OperationFailure.unavailable }
        var results = [String?](repeating: nil, count: count)
        for (offset, match) in matches.enumerated() {
            guard let id = Int(ns.substring(with: match.range(at: 1))), results.indices.contains(id), results[id] == nil else { throw OperationFailure.unavailable }
            let start = NSMaxRange(match.range)
            let end = offset + 1 < matches.count ? matches[offset + 1].range.location : ns.length
            let value = ns.substring(with: NSRange(location: start, length: end - start)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !value.contains("[[RT:") else { throw OperationFailure.unavailable }
            results[id] = value
        }
        return try results.map { guard let value = $0 else { throw OperationFailure.unavailable }; return value }
    }
    func run(image source: CGImage, lines: [OCR.Line], settings: AppSettings) {
        clear()
        guard allowed() else { fail("输入保护检查未通过，操作已停止。请检查安全输入状态和辅助功能权限后重试。"); return }
        guard !lines.isEmpty, lines.count <= 200, lines.allSatisfy({ !$0.text.contains("[[RT:") && $0.rect.width > 0 && $0.rect.height > 0 }) else {
            fail("没有找到可翻译的文字区域，或区域过多。请重新识别或缩小选区。"); return
        }
        let text = Self.batchText(lines)
        guard text.utf8.count <= 12_000 else { fail("整图文字过多，请缩小选区后重试。"); return }
        let template = OperationTemplate(id: "translate", name: "覆盖式翻译", icon: ScreenshotSymbols.translate,
            prompt: "将每个编号后的文字翻译成 {{target}}。严格保留全部 [[RT:数字]] 标记与编号，每个区域单独翻译，不合并、不遗漏。末尾保留 [[RT:END]]。只输出编号及译文，不加说明、代码围栏或其他内容。")
        let snapshot = ContentSnapshot(text: text, source: .init(pid: ProcessInfo.processInfo.processIdentifier, applicationName: "覆盖式翻译"), method: .screenshotOCR)
        let session = OperationSession(snapshot: snapshot)
        let current = generation
        phase = .running; runner.start()
        let events = runner.run(.init(session: session, template: template, settings: settings))
        task = Task { [weak self] in
            for await event in events {
                guard let self, current == self.generation, !Task.isCancelled else { return }
                guard self.allowed() else { self.fail("输入保护检查未通过，操作已停止。请检查安全输入状态和辅助功能权限后重试。"); return }
                switch event {
                case .started: break
                case .thinking: self.thinking = true
                case .engine(let engine): self.engine = engine
                case .delta: self.thinking = false
                case .cancelled: self.cancel(); return
                case .failed: self.fail("翻译未完成，请检查离线语言包或 AI 连接后重试。"); return
                case .completed(let result):
                    guard result.session.id == session.id, result.session.snapshot == snapshot else { self.fail("结果已失效，请重试。"); return }
                    do {
                        let translations = try Self.parse(result.text, count: lines.count)
                        let worker = Task.detached(priority: .userInitiated) { try ScreenshotTranslatedImageRenderer.render(source, lines: lines, translations: translations) }
                        let output = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                        guard current == self.generation, !Task.isCancelled else { return }
                        guard self.allowed() else { self.fail("输入保护检查未通过，操作已停止。请检查安全输入状态和辅助功能权限后重试。"); return }
                        self.image = output; self.engine = result.engine; self.phase = .done; self.thinking = false; self.task = nil
                    } catch {
                        guard current == self.generation, !Task.isCancelled else { return }
                        self.fail(error is ScreenshotTranslatedImageRenderer.Failure
                            ? "译文无法完整放入文字框，请缩小翻译范围或改用文字翻译。"
                            : "译文未能与原图文字区域完整对应，未生成译图。请重试或切换翻译方式。")
                    }
                    return
                }
            }
            guard let self, current == self.generation, !Task.isCancelled else { return }
            self.fail("翻译提前结束，未生成译图。请重试。")
        }
    }
    private func fail(_ message: String) { clear(); phase = .failed; notice = message }
    isolated deinit { task?.cancel(); runner.stop() }
}
