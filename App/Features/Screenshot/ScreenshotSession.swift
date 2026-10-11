import AppKit
import Observation
import RoarkTCore
import RoarkTPlatform

/// Ephemeral image and work owned by one preview. Closing invalidates every asynchronous result.
@MainActor @Observable final class ScreenshotSession {
    private(set) var image: CGImage?
    let origin: String
    let visual: ScreenshotVisualAI
    let translation: ScreenshotTranslation
    private var textWasEdited = false
    var text = "" { didSet { if text != oldValue { textWasEdited = true; translation.clear(); visual.clear() } } }
    enum OCRPhase { case idle, running, done, empty, failed, cancelled }
    private(set) var ocrPhase: OCRPhase = .idle
    private(set) var ocrFinished = false
    private(set) var ocrLines: [OCR.Line] = []
    var ocrLanguages: [String]
    var mergeParagraphs = false
    private var localBusy = false
    var busy: Bool { localBusy || visual.isBusy }
    var result: String { visual.output }
    var engine: String { visual.model }
    var notice: String?
    var confirmingImage: Bool { visual.phase == .confirming }
    var onClose: () -> Void = {}
    var performText: (OperationRequest) -> Void = { _ in }
    var imageCompleted: (OperationResult, OperationTemplate) -> Void = { _, _ in }
    var configureVision: () -> Void = {}
    @ObservationIgnored private let rememberImageConfirmation: (Bool) -> Void
    @ObservationIgnored private let settings: () -> AppSettings
    @ObservationIgnored private let verified: (AIConnectionSettings, String) -> Bool
    @ObservationIgnored private let allowed: () -> Bool
    @ObservationIgnored private let recognize: ((Data) async throws -> String)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var protection: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var savePanel: NSSavePanel?
    @ObservationIgnored private var closed = false

    init(image: CGImage, origin: String, settings: @escaping () -> AppSettings,
         verified: @escaping (AIConnectionSettings, String) -> Bool,
         allowed: @escaping () -> Bool = { SecureInput.status() == .allowed },
         recognize: ((Data) async throws -> String)? = nil,
         translationRunner: (any OperationRunner)? = nil,
         rememberImageConfirmation: @escaping (Bool) -> Void = { _ in },
         sendVisual: ScreenshotVisualAI.Send? = nil) {
        self.rememberImageConfirmation = rememberImageConfirmation
        self.visual = ScreenshotVisualAI(settings: settings, verified: verified, allowed: allowed,
            remember: rememberImageConfirmation, send: sendVisual)
        self.translation = ScreenshotTranslation(runner: translationRunner ?? DefaultOperationRunner(
            offline: TextTranslationXPCClient(), apiKey: { try Keychain().get(account: settings().ai.id) ?? "" },
            isAllowed: allowed), allowed: allowed)
        self.image = image; self.origin = origin; self.settings = settings; self.verified = verified
        self.ocrLanguages = settings().screenshot.ocrLanguages
        self.allowed = allowed; self.recognize = recognize
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
        translation.cancel(); visual.cancel()
        if ocrPhase == .running { ocrPhase = .cancelled; notice = "识别已取消，可以重新开始。" }
        generation += 1; task?.cancel(); task = nil; localBusy = false
    }
    func close() {
        guard !closed else { return }
        closed = true; cancel(); translation.clear(); visual.clear(); protection?.cancel(); protection = nil
        savePanel?.cancel(nil); savePanel = nil
        image = nil; ocrLines = []; text = ""; notice = nil; onClose()
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
    func runOCR(copyAfter: Bool = false, thenVisual action: ScreenshotAIService.Action? = nil, forceConfirmation: Bool = false) {
        guard check(), let data = png() else { return }
        cancel(); let current = generation; localBusy = true; notice = "本机识别中…"; ocrFinished = false
        translation.clear(); visual.clear(); ocrPhase = .running
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
                self.ocrPhase = output.isEmpty ? .empty : .done
                self.text = output; self.ocrFinished = true; self.localBusy = false
                self.notice = output.isEmpty ? "没有识别到文字，可输入文字或换用更清晰的图片。" : nil
                if copyAfter && !output.isEmpty { self.copyText(output) }
                if let action { self.prepareImage(action: action, forceConfirmation: forceConfirmation) }
            } catch {
                guard self.check(current), !Task.isCancelled else { return }
                self.localBusy = false; self.ocrPhase = .failed; self.notice = "本机识别失败，请重试。"
            }
        }
    }
    func translate() {
        guard check(), !busy else { return }
        translation.run(text: text, settings: settings())
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
    var visionModel: String? { visual.visionModel }
    func prepareImage(action: ScreenshotAIService.Action = .explain, forceConfirmation: Bool = false) {
        guard check(), visionModel != nil else { notice = "请先配置并测试视觉模型的图片能力。"; return }
        if !ocrFinished && !textWasEdited {
            runOCR(thenVisual: action, forceConfirmation: forceConfirmation); return
        }
        cancel(); notice = nil
        guard let data = png() else { return }
        visual.prepare(action: action, png: data, text: text, forceConfirmation: forceConfirmation)
    }
    func confirmImage(skipFuture: Bool = false) {
        guard check() else { return }
        visual.confirm(skipFuture: skipFuture)
    }
    func restoreImageConfirmation() { rememberImageConfirmation(false); notice = "已恢复每次发送前确认。" }
    func retryImage() { prepareImage(action: visual.action, forceConfirmation: true) }
    func openImageFollowup() {
        guard check(), let (result, template) = visual.completedResult(origin: origin) else { return }
        imageCompleted(result, template)
    }
    static let imageTemplate = ScreenshotVisualAI.template(.explain)
    static func imageTemplate(forID id: String) -> OperationTemplate? {
        [ScreenshotAIService.Action.translate, .summarize, .explain].map(ScreenshotVisualAI.template).first { $0.id == id }
    }

    isolated deinit { task?.cancel(); protection?.cancel() }
}
