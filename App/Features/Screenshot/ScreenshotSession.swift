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
    private(set) var ocrLines: [OCR.Line] = []
    var ocrLanguages: [String]
    var mergeParagraphs = false
    private(set) var busy = false
    private(set) var result = ""
    private(set) var engine = ""
    var notice: String?
    var confirmingImage = false
    var onClose: () -> Void = {}
    var performText: (OperationRequest) -> Void = { _ in }
    var imageCompleted: (OperationResult, OperationTemplate) -> Void = { _, _ in }
    var configureVision: () -> Void = {}
    @ObservationIgnored private let settings: () -> AppSettings
    @ObservationIgnored private let verified: (AIConnectionSettings, String) -> Bool
    @ObservationIgnored private let allowed: () -> Bool
    @ObservationIgnored private let recognize: ((Data) async throws -> String)?
    @ObservationIgnored private let sendImage: (AIConnectionSettings, String, Data) async throws -> String
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var protection: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pendingConnection: AIConnectionSettings?
    @ObservationIgnored private var pendingModel: String?
    @ObservationIgnored private var savePanel: NSSavePanel?
    @ObservationIgnored private var closed = false

    init(image: CGImage, origin: String, settings: @escaping () -> AppSettings,
         verified: @escaping (AIConnectionSettings, String) -> Bool,
         allowed: @escaping () -> Bool = { SecureInput.status() == .allowed },
         recognize: ((Data) async throws -> String)? = nil,
         sendImage: @escaping (AIConnectionSettings, String, Data) async throws -> String = { connection, model, data in
             let key = try Keychain().get(account: connection.id) ?? ""
             return try await AIClient(connection: connection).complete(text: "请用中文解释这张图片。", apiKey: key,
                 model: model, imageDataURL: "data:image/png;base64," + data.base64EncodedString())
         }) {
        self.image = image; self.origin = origin; self.settings = settings; self.verified = verified
        self.ocrLanguages = settings().screenshot.ocrLanguages
        self.allowed = allowed; self.recognize = recognize; self.sendImage = sendImage
    }
    func start() {
        guard protection == nil, !closed else { return }
        protection = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self else { return }
                if !self.allowed() { self.close(); return }
            }
        }
    }
    func cancel() {
        generation += 1; task?.cancel(); task = nil; busy = false
        confirmingImage = false; pendingConnection = nil; pendingModel = nil
    }
    func close() {
        guard !closed else { return }
        closed = true; cancel(); protection?.cancel(); protection = nil
        savePanel?.cancel(nil); savePanel = nil
        image = nil; ocrLines = []; text = ""; result = ""; notice = nil; onClose()
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
                guard let data = ScreenshotExport.encode(image, jpeg: format == .jpeg) else { throw PlatformReadError.writeFailed }
                try data.write(to: url, options: .atomic); self.notice = "图片已保存"
            } catch { self.notice = "无法保存图片，请选择其他位置后重试。" }
        }
    }
    func runOCR(copyAfter: Bool = false) {
        guard check(), let data = png() else { return }
        cancel(); let current = generation; busy = true; notice = "本机识别中…"; ocrFinished = false
        let languages = ocrLanguages, paragraphs = mergeParagraphs
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let recognized: OCR.Result
                if let recognize = self.recognize { recognized = .init(lines: [.init(text: try await recognize(data), rect: .zero)]) }
                else { recognized = try await OCR().recognize(data, languages: languages) }
                let output = recognized.formatted(paragraphs: paragraphs)
                guard !Task.isCancelled, self.check(current) else { return }
                self.ocrLines = recognized.lines
                self.text = output; self.ocrFinished = true; self.busy = false
                self.notice = output.isEmpty ? "没有识别到文字，可输入文字或换用更清晰的图片。" : nil
                if copyAfter && !output.isEmpty { self.copyText(output) }
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
        cancel(); notice = nil
        let snapshot = ContentSnapshot(text: text, source: .init(pid: ProcessInfo.processInfo.processIdentifier,
            applicationName: "截图 OCR"), method: .screenshotOCR)
        performText(OperationRequest(session: OperationSession(snapshot: snapshot), template: template, settings: config))
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
        task = Task { [weak self] in
            guard let self else { return }
            do {
                // Confirmation and task execution can be separated by a settings/key change.
                guard self.check(current), connection == self.settings().ai, model == self.visionModel else {
                    self.busy = false
                    self.notice = "连接、模型或密钥测试状态已变化，请重新预览并确认。"
                    return
                }
                let answer = try await self.sendImage(connection, model, data)
                guard !Task.isCancelled, self.check(current) else { return }
                self.result = answer; self.busy = false
                if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.notice = "模型未返回内容，请重试。"
                } else {
                    // History retains the explanation, never image bytes. Follow-ups use completed text only.
                    let template = Self.imageTemplate
                    let snapshot = ContentSnapshot(text: "图片理解：追问基于已完成的文字解释，原图不保留在对话中。",
                        source: .init(pid: ProcessInfo.processInfo.processIdentifier, applicationName: self.origin), method: .screenshotOCR)
                    let session = OperationSession(snapshot: snapshot,
                        turns: [OperationTurn(question: "请用中文解释这张图片。", answer: answer)])
                    self.imageCompleted(OperationResult(session: session, templateID: template.id, text: answer, engine: model), template)
                }
            } catch {
                guard !Task.isCancelled, self.check(current) else { return }
                self.busy = false; self.notice = Self.message(.ai(error as? AIClientError ?? .network))
            }
        }
    }
    static let imageTemplate = OperationTemplate(id: "screenshot-image-explanation", name: "图片理解", icon: "photo",
        prompt: "请根据已完成的图片文字解释回答问题。你无法查看原图；需要图片细节时请说明并请用户重新打开图片。")

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
    isolated deinit { task?.cancel(); protection?.cancel() }
}
