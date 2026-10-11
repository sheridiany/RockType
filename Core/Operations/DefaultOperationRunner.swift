import Foundation

/// Offline transport supplied by the App's authenticated XPC adapter.
@MainActor
public protocol TextTranslationClient: AnyObject {
    func translate(sessionID: UUID, generation: UInt64, text: String, target: String) async throws -> String
    func cancel(sessionID: UUID, throughGeneration: UInt64)
    func stop()
}

/// Each window owns a runner; only the window's latest generation can produce events.
@MainActor
public final class DefaultOperationRunner: OperationRunner {
    public typealias AIStream = @Sendable (AIConnectionSettings, String, String, String,
        @escaping @Sendable (String) async -> Void) async throws -> String
    private let key: () throws -> String
    private let providerKey: ((String) throws -> String)?
    private var receivedOutput = false
    private let isAllowed: () -> Bool
    private let offline: (any TextTranslationClient)?
    private let recent: (any RecentResults)?
    private let streamAI: AIStream?
    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?
    private var protectionTask: Task<Void, Never>?
    private var continuation: AsyncStream<OperationEvent>.Continuation?
    private var activeSession: UUID?

    /// isAllowed must fail closed for Secure Input/password fields or unavailable protection state.
    /// key should fetch the current connection's credential from Keychain on demand.
    public init(offline: (any TextTranslationClient)? = nil, recent: (any RecentResults)? = nil,
                apiKey: @escaping () throws -> String, isAllowed: @escaping () -> Bool,
                streamAI: AIStream? = nil, providerKey: ((String) throws -> String)? = nil) {
        self.offline = offline; self.recent = recent; self.key = apiKey
        self.isAllowed = isAllowed; self.streamAI = streamAI; self.providerKey = providerKey
    }

    public func start() {}
    public func stop() { cancel(); offline?.stop() }
    public func cancel() {
        guard continuation != nil else { return }
        if let activeSession { offline?.cancel(sessionID: activeSession, throughGeneration: generation) }
        task?.cancel(); task = nil
        protectionTask?.cancel(); protectionTask = nil
        continuation?.yield(.cancelled); continuation?.finish(); continuation = nil
        activeSession = nil
    }

    public func run(_ request: OperationRequest) -> AsyncStream<OperationEvent> {
        cancel()
        generation &+= 1
        receivedOutput = false
        let current = generation
        let (events, sink) = AsyncStream<OperationEvent>.makeStream()
        continuation = sink
        activeSession = request.session.id
        sink.yield(.started(generation: current))
        sink.onTermination = { [weak self] _ in
            Task { @MainActor in
                guard self?.generation == current else { return }
                self?.cancel()
            }
        }
        task = Task { [weak self] in await self?.execute(request, generation: current) }
        // Cancel even when a transport is waiting without yielding any data.
        protectionTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self, self.generation == current, self.continuation != nil else { return }
                if !self.isAllowed() { self.rejectProtected(); return }
            }
        }
        return events
    }

    private func rejectProtected() {
        if let activeSession { offline?.cancel(sessionID: activeSession, throughGeneration: generation) }
        task?.cancel(); task = nil
        finish(.failed(.protectedInput))
    }

    private func check(_ current: UInt64) throws {
        try Task.checkCancellation()
        guard current == generation, continuation != nil else { throw CancellationError() }
        guard isAllowed() else { throw OperationFailure.protectedInput }
    }

    private func execute(_ request: OperationRequest, generation current: UInt64) async {
        do {
            try check(current)
            guard request.template.input == .text else { throw OperationFailure.unsupportedInput }
            guard !request.session.snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  request.question == nil || !request.question!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw OperationFailure.emptyInput }
            let target = Self.targetLanguage(request.settings.translation.targetLanguage,
                                             text: request.session.snapshot.text)
            let prompt = Self.prompt(request, target: target)
            guard request.maximumInputBytes > 0, prompt.utf8.count <= request.maximumInputBytes else {
                throw OperationFailure.inputTooLong(limit: max(0, request.maximumInputBytes))
            }
            let isTranslation = request.template.id == "translate"
            var text: String?
            var engine = ""
            // Follow-ups always use AI with completed conversation context.
            if isTranslation, request.question == nil, request.settings.translation.engine == .offlineFirst,
               let offline {
                do {
                    let translated = try await offline.translate(sessionID: request.session.id, generation: current,
                        text: request.session.snapshot.text, target: target)
                    try check(current)
                    guard !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw OperationFailure.unavailable
                    }
                    text = translated; engine = "Apple Translation"
                    continuation?.yield(.engine(engine)); continuation?.yield(.delta(translated))
                } catch {
                    try check(current) // cancellation/protection never falls back to network
                    if error is CancellationError || (error as? AIClientError) == .cancelled { throw CancellationError() }
                }
            }
            if text == nil {
                try check(current)
                let route = try AIProviderRouting.resolve(request.settings,
                    task: request.question == nil && isTranslation ? .translation : .assistant,
                    modelOverride: request.template.model)
                let credential: String
                do { credential = try providerKey?(route.connection.id) ?? key() }
                catch { throw AIClientError.configuration }
                try check(current)
                engine = Self.engineLabel(route.connection, model: route.model)
                continuation?.yield(.engine(engine))
                do {
                    text = try await send(route.connection, prompt: prompt, credential: credential, model: route.model, current: current)
                } catch {
                    try check(current)
                    guard let fallback = AIProviderRouting.fallback(for: route.connection, primary: route.model,
                        error: error, hasVisibleOutput: receivedOutput) else { throw error }
                    engine = Self.engineLabel(route.connection, model: fallback) + " · 备用模型"
                    continuation?.yield(.engine(engine))
                    text = try await send(route.connection, prompt: prompt, credential: credential, model: fallback, current: current)
                }
            }
            try check(current)
            let answer = text ?? ""
            guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OperationFailure.unavailable
            }
            let turn = OperationTurn(question: request.question ?? "", answer: answer)
            let session = OperationSession(id: request.session.id, snapshot: request.session.snapshot,
                turns: request.session.turns + [turn])
            let result = OperationResult(session: session, templateID: request.template.id, text: answer, engine: engine)
            if request.settings.privacy.keepRecentResultsInMemory { recent?.add(result) }
            finish(.completed(result))
        } catch {
            guard generation == current, continuation != nil else { return }
            if !isAllowed() || (error as? OperationFailure) == .protectedInput {
                rejectProtected()
            } else if Task.isCancelled || error is CancellationError || (error as? AIClientError) == .cancelled {
                finish(.cancelled)
            } else if let failure = error as? OperationFailure { finish(.failed(failure)) }
            else if let failure = error as? AIClientError { finish(.failed(.ai(failure))) }
            else { finish(.failed(.unavailable)) }
        }
    }

    private static func engineLabel(_ connection: AIConnectionSettings, model: String) -> String {
        let name = connection.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? model : name + " · " + model
    }

    private func send(_ connection: AIConnectionSettings, prompt: String, credential: String,
                      model: String, current: UInt64) async throws -> String {
        try check(current)
        if let streamAI {
            return try await streamAI(connection, prompt, credential, model) { [weak self] delta in
                await self?.receive(delta, generation: current)
            }
        }
        return try await AIClient(connection: connection, requestAllowed: { [weak self] in
            await self?.allowedForTransport(current) ?? false
        }).stream(text: prompt, apiKey: credential,
            model: model, onThinking: { [weak self] in await self?.thinking(generation: current) }) { [weak self] delta in
                await self?.receive(delta, generation: current)
            }
    }

    private func allowedForTransport(_ current: UInt64) -> Bool {
        current == generation && continuation != nil && isAllowed()
    }

    private func thinking(generation current: UInt64) {
        guard generation == current, continuation != nil else { return }
        guard isAllowed() else { rejectProtected(); return }
        continuation?.yield(.thinking)
    }

    private func receive(_ delta: String, generation current: UInt64) {
        guard generation == current, continuation != nil else { return }
        guard isAllowed() else { rejectProtected(); return }
        if !delta.isEmpty { receivedOutput = true; continuation?.yield(.delta(delta)) }
    }

    private func finish(_ event: OperationEvent) {
        continuation?.yield(event); continuation?.finish(); continuation = nil
        protectionTask?.cancel(); protectionTask = nil
        task = nil; activeSession = nil
    }

    public static func targetLanguage(_ configured: String, text: String) -> String {
        guard configured == "auto" else { return configured }
        return text.unicodeScalars.contains { (0x3400...0x4DBF).contains($0.value)
            || (0x4E00...0x9FFF).contains($0.value) || (0x20000...0x3134F).contains($0.value) } ? "en" : "zh-Hans"
    }

    private static func prompt(_ request: OperationRequest, target: String) -> String {
        var text = OperationPrompts.resolved(request.template).replacingOccurrences(of: "{{target}}", with: target)
        if request.question != nil {
            text = "这是同一会话的追问。请直接回答最后一个 question，遵循该问题要求的语言与格式；最初操作仅作为背景，不要再次执行。\n<initial_task>\n" + text + "\n</initial_task>"
        }
        text += "\n\n<content>\n" + request.session.snapshot.text + "\n</content>"
        for turn in request.session.turns {
            text += "\n\n<question>\n" + turn.question + "\n</question>\n<answer>\n" + turn.answer + "\n</answer>"
        }
        if let question = request.question { text += "\n\n<question>\n" + question + "\n</question>" }
        return text
    }
}
