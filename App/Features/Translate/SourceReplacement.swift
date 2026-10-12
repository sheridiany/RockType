import AppKit
import ApplicationServices
import Carbon
import Observation
import SwiftUI
import RoarkTCore
import RoarkTPlatform

/// A live, editable selection identity. Never retained in history or on disk.
@MainActor final class ReplacementTarget {
    private let source: OperationSource
    private let application: AXUIElement
    private let element: AXUIElement
    private let selection: CFRange
    private let original: String
    init?(source: OperationSource?, snapshot: ContentSnapshot) {
        guard SecureInput.status() == .allowed, let source, source.pid == snapshot.source.pid,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == source.pid else { return nil }
        let application = AXUIElementCreateApplication(source.pid)
        AXUIElementSetMessagingTimeout(application, 0.1)
        guard let element = Self.focused(application) else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.1)
        guard Self.editable(element), let selection = Self.range(element), selection.length > 0,
              Self.attribute(kAXSelectedTextAttribute, element) as? String == snapshot.text else { return nil }
        self.source = source; self.application = application; self.element = element
        self.selection = selection; original = snapshot.text
    }
    var foregroundMatches: Bool {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return pid == source.pid || pid == ProcessInfo.processInfo.processIdentifier
    }
    func activate() -> Bool { source.returnToSource() != .unavailable }
    func validate() -> Bool {
        guard SecureInput.status() == .allowed,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == source.pid,
              let focused = Self.focused(application), CFEqual(focused, element), Self.editable(element),
              let current = Self.range(element), current.location == selection.location, current.length == selection.length else { return false }
        return Self.attribute(kAXSelectedTextAttribute, element) as? String == original
    }
    func postPaste() throws {
        guard validate(), let events = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: events, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: events, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { throw PlatformReadError.sourceChanged }
        down.flags = .maskCommand; up.flags = .maskCommand
        // Address only the captured process; never broadcast a paste to a newly active app.
        down.postToPid(source.pid); up.postToPid(source.pid)
    }
    private static func attribute(_ key: String, _ element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }
    private static func focused(_ application: AXUIElement) -> AXUIElement? {
        guard let value = attribute(kAXFocusedUIElementAttribute, application), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private static func editable(_ element: AXUIElement) -> Bool {
        guard let role = attribute(kAXRoleAttribute, element) as? String,
              role != kAXSecureTextFieldSubrole,
              attribute(kAXSubroleAttribute, element) as? String != kAXSecureTextFieldSubrole else { return false }
        var writable = DarwinBoolean(false)
        for key in [kAXSelectedTextAttribute, kAXValueAttribute] {
            if AXUIElementIsAttributeSettable(element, key as CFString, &writable) == .success && writable.boolValue { return true }
        }
        return false
    }
    private static func range(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(kAXSelectedTextRangeAttribute, element), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }
}

/// A single clipboard transaction across all result windows. Dependencies allow isolated tests.
@MainActor final class ReplacementPasteTransaction {
    static let shared = ReplacementPasteTransaction()
    @MainActor struct ClipboardAccess {
        var count: @MainActor () -> Int
        var save: @MainActor () throws -> ClipboardSnapshot
        var write: @MainActor (String, UUID) throws -> Int
        var owns: @MainActor (UUID, Int) -> Bool
        var empty: @MainActor (Int) -> Bool
        var restore: @MainActor (ClipboardSnapshot, Int) throws -> Bool
        static func system(_ board: NSPasteboard = .general, readable: @escaping @MainActor () -> Bool = { SecureInput.status() == .allowed }) -> Self {
            let marker = NSPasteboard.PasteboardType(Identifiers.appBundleID + ".replacement-transaction")
            return Self(count: { board.changeCount }, save: {
                guard readable() else { throw PlatformReadError.secureInput }
                let items = try (board.pasteboardItems ?? []).map { item in
                    var types: [String: Data] = [:]
                    for type in item.types {
                        guard let data = item.data(forType: type) else { throw PlatformReadError.unavailable }
                        types[type.rawValue] = data
                    }
                    return types
                }
                return ClipboardSnapshot(items: items)
            }, write: { text, token in
                let item = NSPasteboardItem()
                guard item.setString(text, forType: .string), item.setString(token.uuidString, forType: marker) else { throw PlatformReadError.writeFailed }
                board.clearContents()
                guard board.writeObjects([item]) else { throw PlatformReadError.writeFailed }
                return board.changeCount
            }, owns: { token, count in
                board.changeCount == count && board.string(forType: marker) == token.uuidString && board.changeCount == count
            }, empty: { count in board.changeCount == count && (board.pasteboardItems ?? []).isEmpty && board.changeCount == count }, restore: { snapshot, expected in
                guard board.changeCount == expected else { return false }
                let items = try snapshot.items.map { types in
                    let item = NSPasteboardItem()
                    for (type, data) in types {
                        guard item.setData(data, forType: .init(type)) else { throw PlatformReadError.writeFailed }
                    }
                    return item
                }
                guard board.changeCount == expected else { return false }
                board.clearContents()
                guard items.isEmpty || board.writeObjects(items) else { throw PlatformReadError.writeFailed }
                return true
            })
        }
    }
    private(set) var busy = false
    private let clipboard: ClipboardAccess
    init(clipboard: ClipboardAccess? = nil) { self.clipboard = clipboard ?? .system() }
    /// Returns whether the original clipboard was restored. A later user copy always wins.
    func paste(_ text: String, allowed: () -> Bool, validate: () -> Bool, post: () throws -> Void,
               settle: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .milliseconds(350)) }) async throws -> Bool {
        guard !busy else { throw PlatformReadError.busy }
        guard !text.isEmpty, allowed(), validate() else { throw PlatformReadError.sourceChanged }
        busy = true; defer { busy = false }
        try Task.checkCancellation()
        let before = clipboard.count(), saved = try clipboard.save()
        guard allowed(), validate(), before == clipboard.count() else { throw PlatformReadError.clipboardChanged }
        let token = UUID()
        let written: Int
        do { written = try clipboard.write(text, token) }
        catch {
            let count = clipboard.count()
            if clipboard.owns(token, count) || (count == before + 1 && clipboard.empty(count)) {
                _ = try clipboard.restore(saved, count)
            }
            throw error
        }
        func restore() throws -> Bool {
            guard clipboard.owns(token, written) else { return false }
            return try clipboard.restore(saved, written)
        }
        do {
            try Task.checkCancellation()
            guard allowed(), validate(), clipboard.owns(token, written) else { throw PlatformReadError.sourceChanged }
            try post()
            // A posted paste may still be queued. Parent cancellation cannot restore its clipboard early.
            try await Task { @MainActor in try await settle() }.value
        } catch {
            _ = try restore(); throw error
        }
        let restored = try restore()
        try Task.checkCancellation()
        return restored
    }
}

@MainActor @Observable final class SourceReplacement {
    private(set) var unavailableReason: String?
    private(set) var busy = false
    @ObservationIgnored private var target: ReplacementTarget?
    @ObservationIgnored private var task: Task<Void, Never>?
    init(source: OperationSource?, snapshot: ContentSnapshot) {
        target = ReplacementTarget(source: source, snapshot: snapshot)
        unavailableReason = target == nil ? "无法确认可编辑的原选区，请复制后自行粘贴。" : nil
    }
    // Used only for deterministic previews; no target means no paste can occur.
    init(previewReason: String?) { target = nil; unavailableReason = previewReason }
    func invalidate(_ reason: String = "来源应用已切换，请重新划词后替换。") { unavailableReason = reason; task?.cancel(); target = nil }
    func refresh() {
        if SecureInput.status() != .allowed { invalidate("当前输入受保护或无法检查，不能替换原文。") }
        else if target?.foregroundMatches == false { invalidate() }
    }
    func replace(_ text: String, feedback: @escaping @MainActor (String) -> Void) {
        refresh()
        guard !busy, unavailableReason == nil, let target, !text.isEmpty else { return }
        busy = true
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false; self.task = nil }
            do {
                guard target.activate() else { throw PlatformReadError.sourceChanged }
                // Activation is asynchronous. Bound the wait and validate again before any write.
                for _ in 0..<20 {
                    try Task.checkCancellation()
                    guard self.unavailableReason == nil, SecureInput.status() == .allowed else { throw PlatformReadError.secureInput }
                    if target.validate() { break }
                    try await Task.sleep(for: .milliseconds(10))
                }
                let restored = try await ReplacementPasteTransaction.shared.paste(text,
                    allowed: { self.unavailableReason == nil && SecureInput.status() == .allowed },
                    validate: target.validate, post: target.postPaste)
                self.unavailableReason = "已向原选区发送粘贴，请在来源应用确认结果。"
                feedback(restored ? "已发送替换，原剪贴板已恢复。" : "已发送替换；保留了期间新复制的内容。")
            } catch is CancellationError { }
            catch { self.invalidate("原选区已失效或替换未完成，请复制后自行粘贴。"); feedback(self.unavailableReason!) }
        }
    }
    func stop() { task?.cancel(); target = nil; unavailableReason = "原选区已释放，请重新划词后替换。" }
    isolated deinit { task?.cancel() }
}

struct SourceReplacementButton: View {
    let replacement: SourceReplacement
    let text: String
    var enabled = true
    let feedback: @MainActor (String) -> Void
    var body: some View {
        Button { replacement.replace(text, feedback: feedback) } label: {
            Image(systemName: "arrow.turn.up.left")
        }
        .buttonStyle(.plain)
        .disabled(!enabled || text.isEmpty || replacement.busy || replacement.unavailableReason != nil)
        .help(replacement.unavailableReason ?? "替换原文；发送粘贴后恢复剪贴板")
        .accessibilityLabel("替换原文")
        .accessibilityHint(replacement.unavailableReason ?? "将结果粘贴回原选区")
    }
}
