import Foundation
import NaturalLanguage
import Observation
import RoarkTCore

/// Presentation-only translation editing. Transport, caches and text protection stay in the runner.
@MainActor @Observable final class TranslateWindowState {
    let result: ResultWindowState
    private(set) var original = ""
    private(set) var sourceLanguage = "auto"
    private(set) var targetLanguage = "zh-Hans"
    private(set) var engine: TranslationSettings.Engine = .offlineFirst
    var expanded = false
    var followupExpanded = false
    private(set) var template: OperationTemplate
    @ObservationIgnored private var snapshot: ContentSnapshot
    @ObservationIgnored private let settings: () -> AppSettings
    @ObservationIgnored private let rememberTarget: (String) -> Void
    @ObservationIgnored private let allowed: () -> Bool
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var revision = 0

    static let languages: [(id: String, title: String)] = [
        ("zh-Hans", "中文"), ("en", "英语"), ("ja", "日语"), ("ko", "韩语"),
        ("fr", "法语"), ("de", "德语"), ("es", "西班牙语")
    ]
    static func accepts(_ template: OperationTemplate) -> Bool {
        template.input == .text && (template.id == "translate" || template.prompt.contains("{{target}}"))
    }
    static func languageName(_ code: String) -> String { languages.first { $0.id == code }?.title ?? code }
    private(set) var detectedLanguage = "en"
    private static func detect(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer(); recognizer.processString(String(text.prefix(1000)))
        let code = recognizer.dominantLanguage?.rawValue ?? "en"
        return code.hasPrefix("zh") ? "zh-Hans" : code
    }
    var sourceLabel: String { sourceLanguage == "auto" ? "自动检测（\(Self.languageName(detectedLanguage))）" : Self.languageName(sourceLanguage) }
    var engineLabel: String {
        if result.engine.hasPrefix("Apple") { return "Apple 离线" }
        return result.engine.isEmpty ? (engine == .ai ? "AI 翻译" : "Apple 优先") : result.engine
    }
    var dictionaryInput: String { original } // T2/T8 slot; no lookup in phase A.

    init(request: OperationRequest, runner: any OperationRunner,
         settings: @escaping () -> AppSettings, rememberTarget: @escaping (String) -> Void = { _ in },
         allowed: @escaping @MainActor () -> Bool, completed: @escaping @MainActor (OperationResult) -> Void = { _ in }, feedback: @escaping @MainActor (String) -> Void = { _ in }) {
        self.settings = settings; self.rememberTarget = rememberTarget; self.allowed = allowed
        template = request.template; snapshot = request.session.snapshot; original = snapshot.text
        let configured = request.settings.translation.targetLanguage
        targetLanguage = configured == "auto" ? DefaultOperationRunner.targetLanguage("auto", text: request.session.snapshot.text) : configured
        engine = request.template.id == "translate" ? request.settings.translation.engine : .ai
        result = ResultWindowState(runner: runner, readable: allowed, completed: completed, feedback: feedback)
        detectedLanguage = Self.detect(request.session.snapshot.text)
    }
    func start(translate: Bool = true) { result.start(); if translate { submit() } }
    func stop() { revision += 1; debounce?.cancel(); debounce = nil; result.stop(); original = ""; snapshot = .init(text: "", source: .init(pid: 0, applicationName: ""), method: .paste) }

    /// Marked text must not start a request. A committed edit cancels stale work immediately.
    func edit(_ text: String, composing: Bool = false) {
        original = text; detectedLanguage = Self.detect(text); revision += 1; debounce?.cancel(); debounce = nil
        result.clear()
        guard allowed(), !composing, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let current = revision
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard let self, current == self.revision else { return }
            self.submit()
        }
    }
    func chooseSource(_ value: String) {
        sourceLanguage = value
        if value != "auto" { engine = .ai } // The Apple XPC contract performs its own detection.
        submit()
    }
    func chooseTarget(_ value: String) {
        guard Self.languages.contains(where: { $0.id == value }) else { return }
        targetLanguage = value; rememberTarget(value); submit()
    }
    func chooseEngine(_ value: TranslationSettings.Engine) {
        guard value != .offlineFirst || template.id == "translate" else { return }
        engine = value
        if value == .offlineFirst { sourceLanguage = "auto" }
        submit()
    }
    func swap() {
        let previousSource = sourceLanguage == "auto" ? detectedLanguage : sourceLanguage
        guard Self.languages.contains(where: { $0.id == previousSource }), result.phase == .done, !result.answer.isEmpty else { return }
        let translated = result.answer
        sourceLanguage = targetLanguage; targetLanguage = previousSource; original = translated
        engine = .ai; detectedLanguage = Self.detect(original); rememberTarget(targetLanguage); submit()
    }
    func submit() {
        revision += 1; debounce?.cancel(); debounce = nil
        guard allowed() else { result.clear(); return }
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { result.clear(); return }
        followupExpanded = false
        let content = ContentSnapshot(text: original, source: snapshot.source, method: snapshot.method, selectionRect: snapshot.selectionRect)
        var config = settings(); config.translation.targetLanguage = targetLanguage; config.translation.engine = engine
        var operation = template
        if sourceLanguage != "auto" {
            operation.prompt = OperationPrompts.resolved(template) + "\n原文语言：" + Self.languageName(sourceLanguage) + "。"
        }
        result.show(.init(session: .init(snapshot: content), template: operation, settings: config))
    }
    func ask() { result.ask(settings: settings()) }
    func showCompleted(_ value: OperationResult) { result.show(value, template: template, settings: settings()) }
    isolated deinit { debounce?.cancel() }
}
