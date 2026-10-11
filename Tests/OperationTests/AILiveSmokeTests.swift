import AppKit
import Foundation
import Testing
import RoarkTCore
import RoarkTPlatform

/// Opt-in only: synthetic content, the user's existing local provider, and a credential held in memory.
/// No app launch, global input, screen capture, settings write or credential output.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["ROARKT_LIVE_AI_SMOKE"] == "1"))
func localMagpieLiveSmoke() async throws {
    // No source is read: AX trust/focus is irrelevant for these built-in fixtures.
    // Still refuse the real network probe while system Secure Input is active.
    guard !SecureInput.isSecureInputActive() else { throw OperationFailure.protectedInput }
    struct Configuration: Decodable { let ai: AIConnectionSettings }
    let configuration = try JSONDecoder().decode(Configuration.self,
        from: Data(contentsOf: SettingsPersistence.defaultURL))
    let connection = configuration.ai
    #expect(connection.baseURL == "http://127.0.0.1:3425/v1")
    #expect(connection.defaultModel == "workbuddy/glm-5.3-flash")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["find-generic-password", "-s", Identifiers.keychainService, "-a", connection.id, "-w"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          let raw = String(data: bytes, encoding: .utf8), !raw.isEmpty else { throw AIClientError.configuration }
    let key = raw.trimmingCharacters(in: .newlines)
    let client = AIClient(connection: connection)
    let capabilities = try await AIConnectionTester(client: client).run(apiKey: key)
    #expect(capabilities.text == .available)
    #expect(capabilities.streaming == .available)
    #expect(capabilities.image == .available)
    #expect(capabilities.cancellation == .available)
    if let latency = capabilities.textLatency { print(String(format: "AI synthetic text probe: %.2f seconds", latency)) }

    // Exercise the real operation runner, auto direction and completed follow-up context.
    var settings = AppSettings.defaults
    settings.ai = connection; settings.translation.engine = .ai
    let runner = DefaultOperationRunner(apiKey: { key }, isAllowed: { !SecureInput.isSecureInputActive() })
    defer { runner.stop() }
    var completed: OperationResult?
    let snapshot = ContentSnapshot(text: "你好，世界。", source: .init(pid: 0, applicationName: "Synthetic probe"), method: .paste)
    for await event in runner.run(.init(session: .init(snapshot: snapshot), template: .defaults[0], settings: settings)) {
        if case .completed(let result) = event { completed = result }
        if case .failed(let failure) = event { throw failure }
    }
    let first = try #require(completed)
    let hasEnglish = first.text.lowercased().contains("hello") && first.text.lowercased().contains("world")
    #expect(hasEnglish)
    completed = nil
    for await event in runner.run(.init(session: first.session, template: .defaults[0], settings: settings,
                                       question: "请把刚才的译文翻译回中文，只输出中文。")) {
        if case .completed(let result) = event { completed = result }
        if case .failed(let failure) = event { throw failure }
    }
    let hasChinese = completed?.text.contains("世界") == true
    #expect(hasChinese)
    #expect(completed?.session.turns.count == 2)

    // A generated image, never real screen content. Use production local Vision OCR.
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 160,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 400, height: 160).fill()
    ("TEST 42" as NSString).draw(at: NSPoint(x: 30, y: 60), withAttributes: [
        .font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black,
    ])
    NSGraphicsContext.restoreGraphicsState()
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    let service = ScreenshotAIService(client: client, recognize: { try await OCR().recognize($0).text }, isAllowed: { !SecureInput.isSecureInputActive() })
    let imageAnswer = try await service.run(action: .explain, png: png,
        model: connection.visionModel ?? connection.defaultModel, imageCapabilityVerified: capabilities.image == .available, apiKey: key)
    let recognizedNumber = imageAnswer.contains("42")
    #expect(recognizedNumber)
}
