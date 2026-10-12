import Foundation
import Observation
import RoarkTCore
import RoarkTPlatform

@MainActor @Observable final class ScreenshotVisualAI {
    enum Phase { case idle, confirming, running, thinking, streaming, done, failed, cancelled }
    struct Request: Sendable {
        let action: ScreenshotAIService.Action
        let png: Data
        let text: String
        let connection: AIConnectionSettings
        let model: String
        var template: OperationTemplate? = nil
        var fallbackImageCapabilityVerified = false
    }
    typealias Send = @MainActor (Request, @escaping @Sendable () async -> Void,
        @escaping @Sendable (String) async -> Void, @escaping @MainActor @Sendable () -> Bool) async throws -> String
    private(set) var phase: Phase = .idle
    private(set) var request: Request?
    private(set) var output = ""
    private(set) var model = ""
    private(set) var customTemplate: OperationTemplate?
    var title: String { customTemplate?.name ?? Self.title(action) }
    private(set) var action: ScreenshotAIService.Action = .explain
    private(set) var notice: String?
    var isBusy: Bool { phase == .running || phase == .thinking || phase == .streaming }
    @ObservationIgnored private let settings: () -> AppSettings
    @ObservationIgnored private let verified: (AIConnectionSettings, String) -> Bool
    @ObservationIgnored private let allowed: () -> Bool
    @ObservationIgnored private let remember: (Bool) -> Void
    @ObservationIgnored private let send: Send?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(settings: @escaping () -> AppSettings, verified: @escaping (AIConnectionSettings, String) -> Bool,
         allowed: @escaping () -> Bool, remember: @escaping (Bool) -> Void,
         send: Send? = nil) {
        self.settings = settings; self.verified = verified; self.allowed = allowed
        self.remember = remember; self.send = send
    }
    static func sender(client: @escaping (AIConnectionSettings) -> AIClient = { AIClient(connection: $0) },
                       apiKey: @escaping (String) throws -> String = { try Keychain().get(account: $0) ?? "" },
                       onModel: @escaping @Sendable (String) async -> Void = { _ in }) -> Send {
        { request, thinking, delta, permitted in
             guard permitted() else { throw OperationFailure.protectedInput }
             let key = try apiKey(request.connection.id)
             guard permitted() else { throw OperationFailure.protectedInput }
             let service = ScreenshotAIService(client: client(request.connection),
                 recognize: { try await OCR().recognize($0).text }, isAllowed: permitted)
             return try await service.run(action: request.action, png: request.png, correctedText: request.text,
                 model: request.model, imageCapabilityVerified: true, apiKey: key,
                 fallbackImageCapabilityVerified: request.fallbackImageCapabilityVerified, customPrompt: request.template?.prompt,
                 onModel: onModel, onThinking: thinking, onDelta: delta)
        }
    }

    var visionModel: String? {
        guard let route = try? AIProviderRouting.resolve(settings(), task: .image) else { return nil }
        let connection = route.connection
        let model = route.model
        return !model.isEmpty && verified(connection, model) ? model : nil
    }
    func clear() {
        generation += 1; task?.cancel(); task = nil; watch?.cancel(); watch = nil
        request = nil; output = ""; model = ""; notice = nil; phase = .idle
    }
    func cancel() {
        guard isBusy || phase == .confirming else { return }
        clear(); phase = .cancelled; notice = "操作已取消，未完成的结果已清除。"
    }
    func prepare(action: ScreenshotAIService.Action, png: Data, text: String, forceConfirmation: Bool = false, template: OperationTemplate? = nil) {
        clear(); self.action = action; customTemplate = template
        guard allowed() else { fail("安全输入已启用，操作已停止。"); return }
        guard let route = try? AIProviderRouting.resolve(settings(), task: .image, modelOverride: template?.model), verified(route.connection, route.model) else { fail("当前视觉模型尚未验证，请先配置并测试图片能力。"); return }
        guard !png.isEmpty, png.count <= 10 * 1024 * 1024 else { fail("图片超过视觉请求的 10 MB 上限，请缩小后重试。"); return }
        guard text.utf8.count <= 32_768 else { fail("文字超过 32 KB，请精简识别文字后重试。"); return }
        let model = route.model
        self.model = model
        request = Request(action: action, png: png, text: text, connection: route.connection, model: model, template: template,
            fallbackImageCapabilityVerified: route.connection.fallbackModel.map { verified(route.connection, $0) } ?? false)
        phase = .confirming
        if settings().screenshot.skipImageAIConfirmation == true && !forceConfirmation { confirm(skipFuture: true) }
    }
    private func valid(_ request: Request) -> Bool {
        allowed() && (request.template.map { settings().templates.contains($0) } ?? true)
            && request.connection == (try? AIProviderRouting.resolve(settings(), task: .image, modelOverride: request.template?.model).connection)
            && request.model == (try? AIProviderRouting.resolve(settings(), task: .image, modelOverride: request.template?.model).model)
            && verified(request.connection, request.model)
            && (!request.fallbackImageCapabilityVerified
                || request.connection.fallbackModel.map { verified(request.connection, $0) } == true)
    }
    func confirm(skipFuture: Bool = false) {
        guard phase == .confirming, let request else { return }
        guard valid(request) else { fail("连接、模型或图片能力已变化，请重新预览并确认。"); return }
        remember(skipFuture)
        phase = .running; notice = nil
        let current = generation
        task = Task { [weak self] in
            guard let self else { return }
            guard self.valid(request), self.generation == current, !Task.isCancelled else {
                if self.generation == current { self.fail("发送条件已变化，请重新确认。"); }
                return
            }
            do {
                let sender = self.send ?? Self.sender(onModel: { [weak self] model in
                    await self?.receiveModel(model, current: current)
                })
                let answer = try await sender(request, { [weak self] in
                    await self?.receiveThinking(current)
                }, { [weak self] value in
                    await self?.receive(value, current: current)
                }, { [weak self] in
                    guard let self else { return false }
                    return self.generation == current && self.valid(request)
                })
                guard !Task.isCancelled, self.generation == current else { return }
                guard self.valid(request) else { self.fail("发送条件已变化，结果已清除。"); return }
                guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.fail("模型未返回完整内容，请重试。"); return
                }
                self.output = answer; self.phase = .done; self.task = nil
                self.request = nil; self.watch?.cancel(); self.watch = nil
            } catch {
                guard !Task.isCancelled, self.generation == current else { return }
                self.fail(Self.message(error))
            }
        }
        watch = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self, self.generation == current, self.isBusy else { return }
                if !self.valid(request) { self.fail("安全输入、连接或模型状态已变化，操作已停止。"); return }
            }
        }
    }
    private func receiveModel(_ value: String, current: Int) {
        guard generation == current, isBusy, let request, valid(request) else { return }
        model = value
    }
    private func receiveThinking(_ current: Int) {
        guard generation == current, isBusy, let request, valid(request), output.isEmpty else { return }
        phase = .thinking
    }
    private func receive(_ value: String, current: Int) {
        guard generation == current, isBusy, let request, valid(request) else { return }
        output += value
        if !output.isEmpty { phase = .streaming }
    }
    private func fail(_ message: String) {
        clear(); phase = .failed; notice = message
    }
    private static func message(_ error: Error) -> String {
        switch error {
        case OperationFailure.protectedInput: "安全输入已启用，操作已停止。"
        case OperationFailure.inputTooLong: "识别文字过长，请精简后重试。"
        case OperationFailure.unsupportedInput: "图片过大或视觉能力不可用，请检查后重试。"
        case AIClientError.unauthorized: "AI 认证失败，请检查密钥和模型权限。"
        case AIClientError.configuration: "请先配置 AI 连接和视觉模型。"
        case AIClientError.timeout: "请求超时，可以重试。"
        case AIClientError.rateLimited: "服务请求过多，请稍后重试。"
        case AIClientError.modelNotFound: "模型不可用，请检查模型名称。"
        default: "图片处理未完成，请检查连接后重试。"
        }
    }
    static func title(_ action: ScreenshotAIService.Action) -> String {
        switch action { case .translate: "截图翻译"; case .summarize: "截图总结"; case .explain: "图片理解" }
    }
    static func template(_ action: ScreenshotAIService.Action) -> OperationTemplate {
        OperationTemplate(id: action == .explain ? "screenshot-image-explanation" : "screenshot-image-" + action.rawValue,
            name: title(action), icon: ScreenshotSymbols.photo, prompt: "请根据已完成的图片文字结果回答问题。你无法查看原图或原始 OCR；需要细节时请说明并请用户重新打开图片。")
    }
    func completedResult(origin: String) -> (OperationResult, OperationTemplate)? {
        guard phase == .done, allowed() else { return nil }
        var template = Self.template(action)
        if let customTemplate { template.id = "screenshot-custom-" + customTemplate.id; template.name = customTemplate.name; template.output = customTemplate.output }
        let snapshot = ContentSnapshot(text: title + "：追问仅基于已完成的文字结果；原图和识别原文不保留在对话中。",
            source: .init(pid: ProcessInfo.processInfo.processIdentifier, applicationName: origin), method: .screenshotOCR)
        let session = OperationSession(snapshot: snapshot, turns: [.init(question: title, answer: output)])
        return (.init(session: session, templateID: template.id, text: output, engine: model), template)
    }
    isolated deinit { task?.cancel(); watch?.cancel() }
}
