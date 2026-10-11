import AppKit
import SwiftUI
import Testing
import RoarkTCore
@testable import RoarkTApp

@Suite(.serialized) @MainActor struct TemplateSettingsTests {
    @Test func templateLifecyclePersistsAndPreservesOtherSettings() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = SettingsPersistence(fileURL: directory.appendingPathComponent("settings.json"))
        let store = SettingsStore(persistence: persistence)
        let item = OperationTemplate(name: "  Synthetic template  ", icon: "sparkles", prompt: "Synthetic prompt", model: " synthetic-model ")
        var settings = store.settings
        try OperationTemplateEdits.save(item, replacing: nil, settings: &settings)
        store.settings = settings; store.flush()
        let reloaded = SettingsStore(persistence: persistence)
        let saved = try #require(reloaded.settings.templates.first { $0.id == item.id })
        #expect(saved.name == "Synthetic template" && saved.model == "synthetic-model")
        #expect(reloaded.settings.selection.toolbarActions.filter { $0 == item.id }.count == 1)
        #expect(!reloaded.settings.selection.disabledActions.contains(item.id))

        var edited = saved
        edited.prompt = "Edited synthetic prompt"
        settings = reloaded.settings
        settings.general.showBeijingTime = true // unrelated edit while the sheet is open
        settings.selection.disabledActions.append(item.id)
        try OperationTemplateEdits.save(edited, replacing: saved, settings: &settings)
        #expect(settings.general.showBeijingTime)
        #expect(settings.selection.disabledActions.contains(item.id)) // editing does not silently re-enable
        try OperationTemplateEdits.delete(edited, settings: &settings)
        #expect(!settings.templates.contains { $0.id == item.id })
        #expect(!settings.selection.toolbarActions.contains(item.id))
        #expect(!settings.selection.disabledActions.contains(item.id))
        #expect(settings.templates == OperationTemplate.defaults)
        reloaded.settings = settings; reloaded.flush()
        #expect(try persistence.load().settings == settings)
    }

    @Test func invalidOrStaleDraftCannotOverwriteSavedSettings() throws {
        var settings = AppSettings()
        let original = settings.templates[0]
        var invalid = original
        invalid.prompt = " \n "
        #expect(throws: (any Error).self) { try OperationTemplateEdits.save(invalid, replacing: original, settings: &settings) }
        #expect(settings == .defaults)
        invalid = original; invalid.name = " "
        #expect(OperationTemplateEdits.validation(invalid) != nil)
        invalid = original; invalid.icon = "nonexistent.synthetic.symbol"
        #expect(OperationTemplateEdits.validation(invalid) != nil)
        invalid = original; invalid.input = .image
        #expect(OperationTemplateEdits.validation(invalid) != nil)
        #expect(throws: (any Error).self) { try OperationTemplateEdits.delete(original, settings: &settings) }
        var edited = original; edited.prompt = "Sheet draft"
        settings.templates[0].prompt = "Newer edit"
        let newer = settings
        #expect(throws: (any Error).self) { try OperationTemplateEdits.save(edited, replacing: original, settings: &settings) }
        #expect(settings == newer)
    }

    @Test func savedPromptAndModelReachRealRunnerThenRestoreDefaults() async throws {
        var settings = AppSettings()
        settings.ai.defaultModel = "synthetic-default"
        settings.translation.engine = .ai
        settings.translation.model = "synthetic-translation"
        settings.selection.assistantModel = "synthetic-assistant"
        let original = settings.templates[0]
        var edited = original; edited.prompt = "Synthetic custom translation to {{target}}"; edited.model = "synthetic-override"
        try OperationTemplateEdits.save(edited, replacing: original, settings: &settings)
        let changed = try await execute(settings.templates[0], settings: settings)
        #expect(changed.engine == "synthetic-override")
        #expect(changed.text.contains("Synthetic custom translation to"))
        #expect(!changed.text.contains("{{target}}"))
        var restored = edited; restored.prompt = original.prompt; restored.model = nil
        try OperationTemplateEdits.save(restored, replacing: edited, settings: &settings)
        let restoredResult = try await execute(settings.templates[0], settings: settings)
        #expect(restoredResult.engine == "synthetic-translation")
        #expect(!restoredResult.text.contains("Synthetic custom translation to"))
        #expect(restoredResult.text.contains("保留段落、空行、标题、列表层级、表格和 Markdown 格式"))
        let assistant = try await execute(settings.templates[1], settings: settings)
        #expect(assistant.engine == "synthetic-assistant")
        settings.selection.assistantModel = OperationTemplateEdits.optionalModel("  \n ")
        let fallback = try await execute(settings.templates[1], settings: settings)
        #expect(fallback.engine == "synthetic-default")
    }

    @Test func imageTemplateGuidesConfigurationAndTextRunnerRejectsIt() async throws {
        var settings = AppSettings()
        settings.ai.defaultModel = "synthetic-text"
        let image = OperationTemplate(name: "Synthetic image", icon: "photo", prompt: "Synthetic prompt", input: .image)
        try OperationTemplateEdits.save(image, replacing: nil, settings: &settings)
        #expect(OperationTemplateEdits.imageNotice(image, settings: settings)?.contains("未配置") == true)
        settings.ai.defaultModelSupportsImages = true
        #expect(OperationTemplateEdits.imageNotice(image, settings: settings)?.contains("仍需") == true)
        // A declared vision model is not advertised as verified; M3 has text snapshots only.
        let runner = DefaultOperationRunner(apiKey: { "synthetic" }, isAllowed: { true }, streamAI: { _, _, _, _, _ in
            Issue.record("Image template must not reach the text transport")
            return "unexpected"
        })
        let request = OperationRequest(session: syntheticSession(), template: image, settings: settings)
        var events: [OperationEvent] = []
        for await event in runner.run(request) { events.append(event) }
        #expect(events.contains(.failed(.unsupportedInput)))
        runner.stop()
    }

    @Test func renderTemplateAndModelSections() throws {
        _ = NSApplication.shared
        var settings = AppSettings()
        settings.ai.defaultModel = "synthetic-default"
        settings.translation.model = "synthetic-translation"
        settings.selection.assistantModel = "synthetic-assistant"
        let image = OperationTemplate(name: "图片解释", icon: "photo", prompt: "请解释这张图片。", input: .image)
        for dark in [false, true] {
            try render(OperationTemplateSettings(settings: .constant(settings), showAIConnection: {}),
                       name: "templates", dark: dark, size: CGSize(width: 540, height: 720))
            try render(OperationModelSettings(settings: .constant(settings), showAIConnection: {}),
                       name: "models", dark: dark, size: CGSize(width: 520, height: 310))
            try render(OperationTemplateEditor(initial: image, original: nil, settings: .constant(settings), showAIConnection: {}),
                       name: "image-editor", dark: dark, size: CGSize(width: 520, height: 640))
        }
    }

    private func execute(_ template: OperationTemplate, settings: AppSettings) async throws -> OperationResult {
        let runner = DefaultOperationRunner(apiKey: { "synthetic" }, isAllowed: { true }, streamAI: { _, prompt, _, model, _ in
            "MODEL:\(model)\n\(prompt)"
        })
        defer { runner.stop() }
        for await event in runner.run(OperationRequest(session: syntheticSession(), template: template, settings: settings)) {
            if case .completed(let result) = event { return result }
        }
        throw OperationFailure.unavailable
    }
    private func syntheticSession() -> OperationSession {
        OperationSession(snapshot: ContentSnapshot(text: "Synthetic content", source: .init(pid: 0, applicationName: "Test"), method: .paste))
    }
    private func render<V: View>(_ view: V, name: String, dark: Bool, size: CGSize) throws {
        let hosting = NSHostingView(rootView: ScrollView { view.padding(16) }
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, dark ? .dark : .light)
            .background(Tokens.palette(dark ? .dark : .light).background))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = hosting
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.displayIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/r4-ai/ui")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    }
}
