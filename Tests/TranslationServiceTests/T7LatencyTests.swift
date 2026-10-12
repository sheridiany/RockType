import Foundation
import Testing
import RoarkTCore
import RoarkTPlatform
@testable import RoarkTTranslationService

@MainActor private final class T7AppleAdapter: TextTranslationClient {
    let backend = SelectionTranslatorFactory.make()
    func translate(sessionID: UUID, generation: UInt64, text: String, target: String) async throws -> String {
        try await backend.translate(text, target: target)
    }
    func cancel(sessionID: UUID, throughGeneration: UInt64) {}
    func stop() {}
}

/// Opt-in: fixed synthetic sentence only. Prints timings/status, never source/output or credentials.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["ROARKT_T7_LIVE"] == "1"))
func t7LiveBackendLatency() async throws {
    let protection = SecureInput.status()
    guard protection == .allowed else { print("t7_live blocked_by_protection \(protection)"); return }
    var settings = AppSettings.defaults
    settings.translation.targetLanguage = "zh-Hans"
    let source = ContentSnapshot(text: "The small window opens quickly.", source: .init(pid: 0, applicationName: "Synthetic"), method: .paste)
    let template = OperationTemplate.defaults.first { $0.id == "translate" }!
    let apple = DefaultOperationRunner(offline: T7AppleAdapter(), apiKey: { throw AIClientError.configuration },
        isAllowed: { SecureInput.status() == .allowed }, translationCache: TranslationResultCache())
    apple.onFirstText = { print(String(format: "t7_live apple_route %@ %.3f ms", $0.engine.rawValue, $0.milliseconds)) }
    for _ in 0..<2 {
        for await event in apple.run(.init(session: .init(snapshot: source), template: template, settings: settings)) {
            if case .failed = event { print("t7_live apple unavailable (no AI fallback credential)") }
        }
    }
    apple.stop()
    guard ProcessInfo.processInfo.environment["ROARKT_T7_LIVE_AI"] == "1" else { return }
    // Uses the configured provider only after the explicit additional opt-in.
    let actual = try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: SettingsPersistence.defaultURL))
    let route = try AIProviderRouting.resolve(actual, task: .translation)
    settings.ai = route.connection; settings.ai.defaultModel = route.model; settings.translation.engine = .ai
    let process = Process(); let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["find-generic-password", "-s", Identifiers.keychainService, "-a", route.connection.id, "-w"]
    process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    guard process.terminationStatus == 0, let raw = String(data: data, encoding: .utf8), !raw.isEmpty else {
        print("t7_live ai credential unavailable"); return
    }
    let credential = raw.trimmingCharacters(in: .newlines)
    let runner = DefaultOperationRunner(apiKey: { credential }, isAllowed: { SecureInput.status() == .allowed },
        translationCache: TranslationResultCache())
    defer { runner.stop() }
    runner.onFirstText = { print(String(format: "t7_live ai_route %@ %.3f ms", $0.engine.rawValue, $0.milliseconds)) }
    for _ in 0..<2 {
        var completed = false
        for await event in runner.run(.init(session: .init(snapshot: source), template: template, settings: settings)) {
            if case .completed = event { completed = true }
        }
        #expect(completed, "Configured synthetic translation must complete")
    }
    let protectedSource = ContentSnapshot(text: "Use `value()` with https://example.invalid/test.\n```swift\nlet sample = 42\n```",
        source: .init(pid: 0, applicationName: "Synthetic"), method: .paste)
    var preserved = false
    for await event in runner.run(.init(session: .init(snapshot: protectedSource), template: template, settings: settings)) {
        if case .completed(let result) = event {
            preserved = result.text.contains("`value()`") && result.text.contains("https://example.invalid/test")
                && result.text.contains("```swift\nlet sample = 42\n```")
        }
    }
    #expect(preserved, "Synthetic code and URL must survive the real provider exactly")
    print("t7_live protected_literals \(preserved ? "pass" : "fail")")

}
