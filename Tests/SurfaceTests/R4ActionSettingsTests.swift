import Foundation
import Testing
import RoarkTCore
@testable import RoarkTApp

@Suite(.serialized) @MainActor struct R4ActionSettingsTests {
    @Test func archiveRoundTripIncludesPlacementAndShortcutButNoConnection() throws {
        var source = AppSettings.defaults
        source.ai.baseURL = "https://synthetic-provider.invalid/v1"
        var custom = OperationTemplate(name: "Synthetic action", icon: "sparkles", prompt: "Synthetic instruction", model: "synthetic-model")
        custom.showInScreenshot = true; custom.shortcut = Shortcut(key: "k", modifiers: [.control, .option])
        try OperationTemplateEdits.save(custom, replacing: nil, settings: &source)
        OperationTemplateEdits.setToolbar(false, id: custom.id, settings: &source)
        OperationTemplateEdits.move(custom.id, by: -1, settings: &source)
        let data = try OperationActionArchive.export(source)
        #expect(!String(decoding: data, as: UTF8.self).contains("synthetic-provider"))
        var destination = AppSettings.defaults
        destination.general.showBeijingTime = true
        try OperationActionArchive.apply(OperationActionArchive.decode(data), to: &destination)
        #expect(destination.templates == source.templates)
        #expect(destination.selection.disabledActions.contains(custom.id))
        #expect(destination.general.showBeijingTime)
        #expect(destination.ai == AppSettings.defaults.ai)
        let encoded = try JSONEncoder().encode(destination)
        #expect(try JSONDecoder().decode(AppSettings.self, from: encoded) == destination)
    }
    @Test func invalidArchiveIsAtomicAndReservedActionsCannotBeShadowed() throws {
        var settings = AppSettings.defaults
        let valid = OperationTemplate(name: "Valid", icon: "sparkles", prompt: "Synthetic")
        let invalid = OperationTemplate(id: "copy", name: "Invalid", icon: "sparkles", prompt: "Synthetic")
        let document = OperationActionArchive.Document(actions: [.init(template: valid, toolbar: true), .init(template: invalid, toolbar: true)])
        #expect(throws: (any Error).self) { try OperationActionArchive.apply(document, to: &settings) }
        #expect(settings == AppSettings.defaults)
        let duplicate = OperationActionArchive.Document(actions: [.init(template: valid, toolbar: true), .init(template: valid, toolbar: false)])
        #expect(throws: (any Error).self) { try OperationActionArchive.apply(duplicate, to: &settings) }
        let unsupported = OperationActionArchive.Document(version: 2, actions: [.init(template: valid, toolbar: true)])
        #expect(throws: (any Error).self) { try OperationActionArchive.apply(unsupported, to: &settings) }
        #expect(throws: (any Error).self) { try OperationActionArchive.decode(Data(repeating: 32, count: 256 * 1024 + 1)) }
    }
    @Test func builtinEditsRestoreAndOrderReachToolbar() throws {
        var settings = AppSettings.defaults
        let original = settings.templates[0]
        var edited = original; edited.name = "Synthetic translation"; edited.prompt = "Custom instruction"
        edited.showInScreenshot = true; edited.shortcut = Shortcut(key: "k", modifiers: .command)
        try OperationTemplateEdits.save(edited, replacing: original, settings: &settings)
        OperationTemplateEdits.move(edited.id, by: 1, settings: &settings)
        #expect(settings.templates[1] == edited)
        let ordered = settings.selection.toolbarActions.filter { id in settings.templates.contains { $0.id == id } }
        #expect(ordered == settings.templates.map(\.id))
        try OperationTemplateEdits.save(original, replacing: edited, settings: &settings)
        #expect(settings.templates[1] == original)
        #expect(settings.templates.allSatisfy { $0.shortcut == nil })
    }
}
