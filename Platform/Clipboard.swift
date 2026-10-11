import AppKit
import Carbon

/// An in-memory snapshot; never persisted or logged. Failure to materialize any type aborts copying.
public struct ClipboardSnapshot: Sendable, Equatable {
    public let items: [[String: Data]]
    public init(items: [[String: Data]]) { self.items = items }
}

@MainActor protocol ClipboardBackend {
    var changeCount: Int { get }
    func snapshot() throws -> ClipboardSnapshot
    func restore(_ snapshot: ClipboardSnapshot) throws
    func string() -> String?
}

@MainActor private struct SystemClipboard: ClipboardBackend {
    let pasteboard: NSPasteboard
    var changeCount: Int { pasteboard.changeCount }
    func snapshot() throws -> ClipboardSnapshot {
        let items = try (pasteboard.pasteboardItems ?? []).map { item in
            var types: [String: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { throw PlatformReadError.unavailable }
                types[type.rawValue] = data
            }
            return types
        }
        return ClipboardSnapshot(items: items)
    }
    func restore(_ snapshot: ClipboardSnapshot) throws {
        let items = snapshot.items.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: .init(type)) }
            return item
        }
        pasteboard.clearContents()
        if !items.isEmpty && !pasteboard.writeObjects(items) { throw PlatformReadError.writeFailed }
    }
    func string() -> String? { pasteboard.string(forType: .string) }
}

@MainActor public final class Clipboard {
    public static let shared = Clipboard()
    private let backend: any ClipboardBackend
    private let checkReadable: @MainActor () throws -> Void
    private let sourcePID: @MainActor () -> pid_t?
    private let postCopy: @MainActor () throws -> Void
    private var copying = false

    public init() {
        backend = SystemClipboard(pasteboard: .general)
        checkReadable = { try SecureInput.requireReadable() }
        sourcePID = { Accessibility.frontmostApplication?.pid }
        postCopy = {
            guard let source = CGEventSource(stateID: .combinedSessionState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else {
                throw PlatformReadError.unavailable
            }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    init(backend: any ClipboardBackend, checkReadable: @escaping @MainActor () throws -> Void,
         sourcePID: @escaping @MainActor () -> pid_t?, postCopy: @escaping @MainActor () throws -> Void) {
        self.backend = backend; self.checkReadable = checkReadable
        self.sourcePID = sourcePID; self.postCopy = postCopy
    }

    public var changeCount: Int { backend.changeCount }
    public func save() throws -> ClipboardSnapshot {
        try checkReadable()
        let before = changeCount
        let snapshot = try backend.snapshot()
        guard before == changeCount else { throw PlatformReadError.clipboardChanged }
        try checkReadable()
        return snapshot
    }
    /// Compare-and-restore; a changed clipboard is never overwritten.
    @discardableResult public func restore(_ snapshot: ClipboardSnapshot, ifUnchanged expected: Int) throws -> Bool {
        guard changeCount == expected else { return false }
        try backend.restore(snapshot)
        return true
    }
    public func readString() throws -> String? {
        try checkReadable()
        let value = backend.string()
        try checkReadable()
        return value
    }
    public func writeString(_ string: String) throws {
        try backend.restore(ClipboardSnapshot(items: [[NSPasteboard.PasteboardType.string.rawValue: Data(string.utf8)]]))
    }
    public func readPNG() throws -> Data? {
        let snapshot = try save()
        for item in snapshot.items {
            if let png = item[NSPasteboard.PasteboardType.png.rawValue] { return png }
            if let tiff = item[NSPasteboard.PasteboardType.tiff.rawValue], let bitmap = NSBitmapImageRep(data: tiff) {
                return bitmap.representation(using: .png, properties: [:])
            }
        }
        return nil
    }
    public func writePNG(_ data: Data) throws {
        try backend.restore(ClipboardSnapshot(items: [[NSPasteboard.PasteboardType.png.rawValue: data]]))
    }

    /// Explicit user action only. No background clipboard monitoring. Never posts paste events.
    public func copySelectionFallback(timeout: Duration = .milliseconds(450)) async throws -> String? {
        guard !copying else { throw PlatformReadError.busy }
        copying = true
        defer { copying = false }
        try Task.checkCancellation()
        try checkReadable()
        guard let pid = sourcePID() else { throw PlatformReadError.unavailable }
        let before = changeCount
        let saved = try save()
        try checkReadable()
        guard changeCount == before else { throw PlatformReadError.clipboardChanged }
        guard sourcePID() == pid else { throw PlatformReadError.sourceChanged }
        try postCopy()
        let deadline = ContinuousClock.now + timeout
        while changeCount == before {
            try Task.checkCancellation()
            try checkReadable()
            guard sourcePID() == pid else { throw PlatformReadError.sourceChanged }
            guard ContinuousClock.now < deadline else { throw PlatformReadError.timeout }
            try await Task.sleep(for: .milliseconds(15))
        }
        let ours = changeCount
        defer { _ = try? restore(saved, ifUnchanged: ours) }
        try Task.checkCancellation()
        try checkReadable()
        guard sourcePID() == pid else { throw PlatformReadError.sourceChanged }
        let text = backend.string()
        try await Task.sleep(for: .milliseconds(30))
        try checkReadable()
        guard sourcePID() == pid else { throw PlatformReadError.sourceChanged }
        guard changeCount == ours else { throw PlatformReadError.clipboardChanged }
        return text
    }
}
