import Foundation
import RoarkTCore

/// Only action definitions and placement flags cross this boundary; no connections or credentials.
@MainActor enum OperationActionArchive {
    struct Entry: Codable { var template: OperationTemplate; var toolbar: Bool }
    struct Document: Codable { var version = 1; var actions: [Entry] }
    enum Failure: Error { case invalid }
    static func export(_ settings: AppSettings) throws -> Data {
        let document = Document(actions: settings.templates.map {
            Entry(template: $0, toolbar: settings.selection.toolbarActions.contains($0.id)
                && !settings.selection.disabledActions.contains($0.id) && $0.input == .text)
        })
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        _ = try decode(data)
        return data
    }
    static func decode(_ data: Data) throws -> Document {
        guard data.count <= 256 * 1024 else { throw Failure.invalid }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.version == 1, !document.actions.isEmpty, document.actions.count <= 100,
              Set(document.actions.map { $0.template.id }).count == document.actions.count else { throw Failure.invalid }
        for entry in document.actions {
            guard OperationTemplateEdits.validation(entry.template) == nil, !entry.toolbar || entry.template.input == .text else { throw Failure.invalid }
        }
        return document
    }
    static func apply(_ document: Document, to settings: inout AppSettings) throws {
        // Validate again at the mutation boundary, then publish all changes at once.
        let encoder = JSONEncoder()
        let checked = try decode(encoder.encode(document))
        var next = settings
        for entry in checked.actions {
            let item = entry.template
            if let old = next.templates.first(where: { $0.id == item.id }) {
                try OperationTemplateEdits.save(item, replacing: old, settings: &next)
            } else {
                try OperationTemplateEdits.save(item, replacing: nil, settings: &next)
            }
            OperationTemplateEdits.setToolbar(entry.toolbar, id: item.id, settings: &next)
        }
        // The file's ordering is authoritative for imported actions; unrelated actions retain order.
        let ids = checked.actions.map { $0.template.id }
        let imported = ids.compactMap { id in next.templates.first { $0.id == id } }
        next.templates = imported + next.templates.filter { !ids.contains($0.id) }
        OperationTemplateEdits.syncOrder(settings: &next)
        settings = next
    }
}

extension OperationTemplateEdits {
    static func setToolbar(_ enabled: Bool, id: String, settings: inout AppSettings) {
        if !settings.selection.toolbarActions.contains(id) { settings.selection.toolbarActions.append(id) }
        settings.selection.disabledActions.removeAll { $0 == id }
        if !enabled { settings.selection.disabledActions.append(id) }
    }
    static func move(_ id: String, by offset: Int, settings: inout AppSettings) {
        guard let index = settings.templates.firstIndex(where: { $0.id == id }),
              settings.templates.indices.contains(index + offset) else { return }
        settings.templates.swapAt(index, index + offset)
        syncOrder(settings: &settings)
    }
    static func syncOrder(settings: inout AppSettings) {
        let present = Set(settings.selection.toolbarActions)
        var ordered = settings.templates.map(\.id).filter { present.contains($0) }.makeIterator()
        let ids = Set(settings.templates.map(\.id))
        // Keep copy/search in their current slots while reordering AI actions.
        settings.selection.toolbarActions = settings.selection.toolbarActions.map { ids.contains($0) ? ordered.next() ?? $0 : $0 }
        while let id = ordered.next() { settings.selection.toolbarActions.append(id) }
    }
}
