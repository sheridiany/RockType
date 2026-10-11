import AppKit
import RoarkTCore
import RoarkTPlatform

/// An immutable snapshot plus a short-lived identity check; never stored in recent results.
@MainActor struct CapturedSelection {
    let snapshot: ContentSnapshot
    let isCurrent: @MainActor () -> Bool
}

@MainActor final class SelectionCapture {
    struct Context {
        let source: ContentSnapshot.Source
        let isCurrent: @MainActor () -> Bool
    }
    struct Reading {
        let status: SelectionReader.Status
        let text: String?
        /// Platform coordinates (top-left origin).
        let rect: CGRect?
    }
    enum Failure: Error { case empty, unavailable, sourceChanged }

    private let allowed: @MainActor () -> Bool
    private let context: @MainActor () -> Context?
    private let read: @MainActor () -> Reading
    private let copy: @MainActor () async throws -> String?
    private let primaryHeight: @MainActor () -> CGFloat

    init(allowed: @escaping @MainActor () -> Bool = { SecureInput.status() == .allowed },
         context: @escaping @MainActor () -> Context? = {
             guard let source = SelectionSource() else { return nil }
             return Context(source: source.source, isCurrent: { source.isCurrent })
         },
         read: @escaping @MainActor () -> Reading = {
             let result = SelectionReader.read()
             return Reading(status: result.status, text: result.text, rect: result.rect)
         },
         copy: @escaping @MainActor () async throws -> String? = { try await Clipboard.shared.copySelectionFallback() },
         primaryHeight: @escaping @MainActor () -> CGFloat = { NSScreen.screens.first?.frame.maxY ?? 0 }) {
        self.allowed = allowed; self.context = context; self.read = read
        self.copy = copy; self.primaryHeight = primaryHeight
    }

    func capture() async throws -> CapturedSelection {
        try Task.checkCancellation()
        guard allowed() else { throw PlatformReadError.secureInput }
        guard let context = context(), context.isCurrent() else { throw Failure.unavailable }
        let reading = read()
        var method: ContentSnapshot.CaptureMethod = .accessibility
        let text: String?
        switch reading.status {
        case .success: text = reading.text
        case .empty: throw Failure.empty
        case .noPermission: throw PlatformReadError.noPermission
        case .secureInput: throw PlatformReadError.secureInput
        case .unsupported:
            guard allowed(), context.isCurrent() else { throw Failure.sourceChanged }
            method = .copyFallback
            text = try await copy()
        }
        try Task.checkCancellation()
        guard allowed(), context.isCurrent() else { throw Failure.sourceChanged }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.empty }
        let rect = reading.rect.map { ScreenGeometry.topLeft($0, primaryHeight: primaryHeight()) }
        return CapturedSelection(snapshot: .init(text: text, source: context.source, method: method,
                                                selectionRect: rect), isCurrent: context.isCurrent)
    }
}

/// Pure policy shared by mouse and explicit shortcut entry points.
enum SelectionPolicy {
    static func permits(_ bundleID: String?, settings: SelectionSettings) -> Bool {
        switch settings.applicationFilter {
        case .blacklist: return bundleID.map { !settings.excludedApplications.contains($0) } ?? true
        case .whitelist: return bundleID.map { settings.includedApplications.contains($0) } ?? false
        }
    }

    static func actions(settings: AppSettings) -> [String] {
        var seen = Set<String>()
        return settings.selection.toolbarActions.filter { id in
            guard seen.insert(id).inserted, !settings.selection.disabledActions.contains(id) else { return false }
            return id == "copy" || id == "search" || settings.templates.contains { $0.id == id && $0.input == .text }
        }
    }
}
