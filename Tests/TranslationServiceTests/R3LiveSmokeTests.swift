import AppKit
import Foundation
import Testing
import RoarkTCore
import RoarkTPlatform
@testable import RoarkTTranslationService

private enum SmokeFailure: Error { case configuration, operation(String), assertion(String) }

/// Built-in synthetic facts only. Do not attach responses, prompts, key material or
/// decoded settings to testing macros: failure diagnostics must remain content-free.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["ROARKT_LIVE_AI_SMOKE"] == "1"))
func r3MagpieFullSmoke() async throws {
    guard !SecureInput.isSecureInputActive() else { throw OperationFailure.protectedInput }
    struct Configuration: Decodable { let ai: AIConnectionSettings }
    let configuration = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: SettingsPersistence.defaultURL))
    let connection = configuration.ai
    guard connection.baseURL == "http://127.0.0.1:3425/v1", connection.defaultModel == "workbuddy/glm-5.3-flash" else {
        throw SmokeFailure.configuration
    }
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["find-generic-password", "-s", Identifiers.keychainService, "-a", connection.id, "-w"]
    process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    guard process.terminationStatus == 0, let raw = String(data: data, encoding: .utf8), !raw.isEmpty else {
        throw SmokeFailure.configuration
    }
    let key = raw.trimmingCharacters(in: .newlines)
    let client = AIClient(connection: connection, requestAllowed: {
        await MainActor.run { !SecureInput.isSecureInputActive() }
    })
    func measured(_ name: String, _ operation: () async throws -> Bool) async throws {
        let start = ContinuousClock.now
        do {
            let correct = try await operation()
            let duration = start.duration(to: .now).components
            let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
            print(String(format: "R3 smoke %@: latency=%.2fs correct=%@", name, seconds, correct ? "true" : "false"))
            guard correct else { throw SmokeFailure.assertion(name) }
        } catch {
            // Never print transport errors or content-bearing values.
            print("R3 smoke \(name): failed")
            throw SmokeFailure.operation(name)
        }
    }
    var imageVerified = false
    try await measured("capabilities") {
        let result = try await AIConnectionTester(client: client).run(apiKey: key)
        imageVerified = result.image == .available
        return result.text == .available && result.streaming == .available && imageVerified && result.cancellation == .available
    }
    var settings = AppSettings.defaults
    settings.ai = connection; settings.translation.engine = .ai; settings.privacy.keepRecentResultsInMemory = false
    let runner = DefaultOperationRunner(apiKey: { key }, isAllowed: { !SecureInput.isSecureInputActive() })
    defer { runner.stop() }
    func run(_ id: String, text: String) async throws -> OperationResult {
        guard let template = settings.templates.first(where: { $0.id == id }) else { throw SmokeFailure.configuration }
        let snapshot = ContentSnapshot(text: text, source: .init(pid: 0, applicationName: "Synthetic probe"), method: .paste)
        for await event in runner.run(.init(session: .init(snapshot: snapshot), template: template, settings: settings)) {
            if case .completed(let result) = event { return result }
            if case .failed = event { throw SmokeFailure.operation(id) }
        }
        throw SmokeFailure.operation(id)
    }
    try await measured("translate") {
        let answer = try await run("translate", text: "你好，世界。").text.lowercased()
        return answer.contains("hello") && answer.contains("world")
    }
    try await measured("summarize") {
        let answer = try await run("summarize", text: "测试有42个样本，其中17个已通过，其余待验。请保留阿拉伯数字。").text
        return answer.contains("42") && answer.contains("17")
    }
    try await measured("polish") {
        let answer = try await run("polish", text: "the test contain 42 item.").text.lowercased()
        return answer.contains("42 items") && answer.contains("test")
    }
    try await measured("explain") {
        let answer = try await run("explain", text: "HTTP 404 表示什么？请用一句中文解释。").text
        return answer.contains("404") && ["未找到", "不存在", "找不到"].contains(where: answer.contains)
    }
    let longSource = (1...90).map { index in
        "第\(index)段：合成测试记录。总计42个样本，其中17个已通过，其余仍待验证。请保留阿拉伯数字。\n\n"
    }.joined()
    try await measured("long-summary") {
        let result = try await run("summarize", text: longSource)
        return result.engine.contains("段合并") && result.text.contains("42") && result.text.contains("17")
    }
    try await measured("long-translate") {
        let result = try await run("translate", text: longSource)
        return result.engine.contains("段") && result.text.contains("42") && result.text.contains("17")
    }
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 160,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0) else { throw SmokeFailure.configuration }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 400, height: 160).fill()
    ("TEST 42" as NSString).draw(at: NSPoint(x: 30, y: 60), withAttributes: [
        .font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black
    ])
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw SmokeFailure.configuration }
    let service = ScreenshotAIService(client: client, recognize: { try await OCR().recognize($0).text },
        isAllowed: { !SecureInput.isSecureInputActive() })
    for action in [ScreenshotAIService.Action.translate, .summarize, .explain] {
        try await measured("image-" + action.rawValue) {
            let answer = try await service.run(action: action, png: png, model: connection.visionModel ?? connection.defaultModel,
                imageCapabilityVerified: imageVerified, apiKey: key)
            return answer.contains("42")
        }
    }
    // Exercise the real service coordinator and its production HTTP completion path;
    // no installed IME or LaunchAgent is touched by this in-process integration smoke.
    let input = InputAICoordinator(), owner = UUID()
    defer { input.removeConnection(owner) }
    let polish = OperationPrompts.resolved(OperationTemplate.defaults[2])
    let values = ["baseURL": connection.baseURL, "model": connection.defaultModel, "apiKey": key, "timeout": "90",
        "rewritePrompt": polish + "\n请改写措辞，保留数字。", "polishPrompt": polish,
        "translatePrompt": OperationPrompts.resolved(OperationTemplate.defaults[0])]
    guard input.configure(values, owner: owner) == nil else { throw SmokeFailure.configuration }
    for action in ["rewrite", "polish", "translate"] {
        try await measured("input-ai-" + action) {
            let source = action == "translate" ? "你好，世界。" : "the test contain 42 item."
            let answer: String? = await withCheckedContinuation { continuation in
                input.rewrite(connectionID: UUID(), sessionID: UUID().uuidString, generation: 1, text: source, action: action) { _, _, result, error in
                    continuation.resume(returning: error == nil ? result : nil)
                }
            }
            guard let answer = answer?.lowercased() else { return false }
            return action == "translate" ? answer.contains("hello") && answer.contains("world") : answer.contains("42") && answer.contains("test")
        }
    }
}
