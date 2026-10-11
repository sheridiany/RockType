import AppKit
import Observation
import RoarkTCore
import RoarkTPlatform

/// Ephemeral image and work owned by one preview. Closing invalidates every asynchronous result.
@MainActor @Observable final class ScreenshotSession {
    private(set) var image: CGImage?
    let origin: String
    var text = ""
    private(set) var ocrFinished = false
    private(set) var busy = false
    private(set) var result = ""
    private(set) var engine = ""
    var notice: String?
    var confirmingImage = false
    var onClose: () -> Void = {}
    var onResult: () -> Void = {}
    var configureVision: () -> Void = {}
    @ObservationIgnored private let settings: () -> AppSettings
    @ObservationIgnored private let verified: (AIConnectionSettings, String) -> Bool
    @ObservationIgnored private let allowed: () -> Bool
    @ObservationIgnored private let recognize: (Data) async throws -> String
    @ObservationIgnored private let sendImage: (AIConnectionSettings, String, Data) async throws -> String
    @ObservationIgnored private let runner: any OperationRunner
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var protection: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pendingConnection: AIConnectionSettings?
    @ObservationIgnored private var pendingModel: String?
    @ObservationIgnored private var savePanel: NSSavePanel?
    @ObservationIgnored private var closed = false

    init(image: CGImage, origin: String, settings: @escaping () -> AppSettings,
         verified: @escaping (AIConnectionSettings, String) -> Bool,
         runner: any OperationRunner,
         allowed: @escaping () -> Bool = { SecureInput.status() == .allowed },
         recognize: @escaping (Data) async throws -> String = { try await OCR().recognize($0).text },
         sendImage: @escaping (AIConnectionSettings, String, Data) async throws -> String = { connection, model, data in
             let key = try Keychain().get(account: connection.id) ?? ""
             return try await AIClient(connection: connection).complete(text: "请用中文解释这张图片。", apiKey: key,
                 model: model, imageDataURL: "data:image/png;base64," + data.base64EncodedString())
         }) {
        self.image = image; self.origin = origin; self.settings = settings; self.verified = verified
        self.runner = runner; self.allowed = allowed; self.recognize = recognize; self.sendImage = sendImage
    }
    func start() {
        guard protection == nil, !closed else { return }
        runner.start()
        protection = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self else { return }
                if !self.allowed() { self.close(); return }
            }
        }
    }
    func cancel() {
        generation += 1; task?.cancel(); task = nil; runner.cancel(); busy = false
        confirmingImage = false; pendingConnection = nil; pendingModel = nil
    }
    func close() {
        guard !closed else { return }
        closed = true; cancel(); runner.stop(); protection?.cancel(); protection = nil
        savePanel?.cancel(nil); savePanel = nil
        image = nil; text = ""; result = ""; notice = nil; onClose()
    }
    private func check(_ current: Int? = nil) -> Bool {
        !closed && allowed() && (current == nil || current == generation)
    }
    func png() -> Data? { image.flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) } }
    func copyImage(closeAfter: Bool = false) {
        guard check(), let data = png() else { return }
        do { try Clipboard.shared.writePNG(data); notice = "图片已复制"; if closeAfter { close() } }
        catch { notice = "无法写入剪贴板，请重试。" }
    }
    func copyText(_ value: String) {
        guard check() else { return }
        do { try Clipboard.shared.writeString(value); notice = "文字已复制" }
        catch { notice = "无法写入剪贴板，请重试。" }
    }
    func save() {
        guard check(), image != nil, savePanel == nil else { return }
        let format = settings().screenshot.format
        let panel = NSSavePanel(); savePanel = panel
        panel.allowedContentTypes = format == .png ? [.png] : [.jpeg]
        panel.nameFieldStringValue = format == .png ? "截图.png" : "截图.jpg"
        panel.begin { [weak self] response in
            guard let self else { return }
            self.savePanel = nil
            guard response == .OK, self.check(), let url = panel.url, let image = self.image else { return }
            do {
                guard let data = NSBitmapImageRep(cgImage: image).representation(using: format == .png ? .png : .jpeg,
                    properties: format == .jpeg ? [.compressionFactor: 0.9] : [:]) else { throw PlatformReadError.writeFailed }
                try data.write(to: url, options: .atomic); self.notice = "图片已保存"
            } catch { self.notice = "无法保存图片，请选择其他位置后重试。" }
        }
    }
    func runOCR() {
        guard check(), let data = png() else { return }
        cancel(); let current = generation; busy = true; notice = "本机识别中…"; ocrFinished = false
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let output = try await self.recognize(data)
                guard !Task.isCancelled, self.check(current) else { return }
                self.text = output; self.ocrFinished = true; self.busy = false
                self.notice = output.isEmpty ? "没有识别到文字，可输入文字或换用更清晰的图片。" : nil
            } catch {
                guard self.check(current), !Task.isCancelled else { return }
                self.busy = false; self.notice = "本机识别失败，请重试。"
            }
        }
    }
    /// Reads the edited value at click time, never the uncorrected OCR result.
    func runText(templateID: String) {
        guard check(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let config = settings()
        guard let template = config.templates.first(where: { $0.id == templateID && $0.input == .text }) else {
            notice = "操作模板不可用，请在设置中恢复。"; return
        }
        cancel(); let current = generation; result = ""; engine = ""; busy = true; notice = nil
        let snapshot = ContentSnapshot(text: text, source: .init(pid: ProcessInfo.processInfo.processIdentifier,
            applicationName: "截图 OCR"), method: .paste)
        let events = runner.run(OperationRequest(session: OperationSession(snapshot: snapshot), template: template, settings: config))
        onResult()
        task = Task { [weak self] in
            guard let self else { return }
            for await event in events {
                guard !Task.isCancelled, self.check(current) else { return }
                switch event {
                case .started: break
                case .engine(let value): self.engine = value
                case .delta(let value): self.result += value
                case .completed(let value): self.result = value.text; self.engine = value.engine; self.busy = false
                case .cancelled: self.busy = false; self.notice = "已取消"
                case .failed(let failure): self.busy = false; self.notice = Self.message(failure)
                }
            }
            if self.check(current) { self.busy = false }
        }
    }
    var visionModel: String? {
        let connection = settings().ai
        let model = connection.visionModel ?? (connection.defaultModelSupportsImages ? connection.defaultModel : "")
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, verified(connection, model) else { return nil }
        return model
    }
    func prepareImage() {
        guard check(), let model = visionModel else { notice = "当前连接的图片能力尚未验证可用，请配置并测试视觉模型。"; return }
        cancel(); pendingConnection = settings().ai; pendingModel = model; confirmingImage = true
    }
    func confirmImage() {
        guard check(), confirmingImage, let connection = pendingConnection, let model = pendingModel,
              connection == settings().ai, model == visionModel, let data = png() else {
            confirmingImage = false; notice = "连接或模型已变化，请重新预览并确认。"; return
        }
        cancel(); let current = generation; busy = true; result = ""; engine = model; notice = nil
        onResult()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let answer = try await self.sendImage(connection, model, data)
                guard !Task.isCancelled, self.check(current) else { return }
                self.result = answer; self.busy = false
                if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self.notice = "模型未返回内容，请重试。" }
            } catch {
                guard !Task.isCancelled, self.check(current) else { return }
                self.busy = false; self.notice = Self.message(.ai(error as? AIClientError ?? .network))
            }
        }
    }
    private static func message(_ failure: OperationFailure) -> String {
        switch failure {
        case .inputTooLong(let limit): "文字超出输入预算（\(limit) 字节），请缩短后重试。"
        case .protectedInput: "安全输入已启用，操作已停止。"
        case .ai(.unauthorized): "AI 认证失败，请检查密钥和模型权限。"
        case .ai(.modelNotFound): "模型不可用，请检查模型名称。"
        case .ai(.rateLimited): "请求过于频繁，请稍后重试。"
        case .ai(.configuration): "请先配置 AI 连接与模型。"
        case .ai(.timeout): "请求超时，请重试。"
        default: "操作失败，请检查连接后重试。"
        }
    }
    isolated deinit { task?.cancel(); protection?.cancel(); runner.stop() }
}
