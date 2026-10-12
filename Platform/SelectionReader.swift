import Foundation
import ApplicationServices

@MainActor public enum SelectionReader {
    public enum Status: Equatable, Sendable { case success, empty, unsupported, noPermission, secureInput }
    public struct Result: Sendable {
        public let status: Status
        public let text: String?
        /// AX already uses global top-left screen coordinates, in points.
        public let rect: CGRect?
        public let source: Accessibility.Application?
    }

    public static func read() -> Result {
        let source = Accessibility.frontmostApplication
        func result(_ status: Status, _ text: String? = nil, _ rect: CGRect? = nil) -> Result {
            Result(status: status, text: text, rect: rect, source: source)
        }
        switch SecureInput.status() {
        case .secureInput: return result(.secureInput)
        case .noPermission: return result(.noPermission)
        case .unavailable: return result(.unsupported)
        case .allowed: break
        }
        guard var element = Accessibility.focusedElement(), let password = SecureInput.isPassword(element) else { return result(.unsupported) }
        guard !password, !SecureInput.isSecureInputActive() else { return result(.secureInput) }
        func resolve(_ element: AXUIElement) -> SelectionTextResolution {
            SelectionTextResolution.read(
                readable: { SecureInput.status() == .allowed && source == Accessibility.frontmostApplication
                    && SecureInput.isPassword(element) == false },
                selected: { Accessibility.attribute(kAXSelectedTextAttribute, of: element) as? String },
                range: { selectedRange(element) },
                string: { range in parameterizedText(element, range: range, attributed: false) },
                attributed: { range in parameterizedText(element, range: range, attributed: true) })
        }
        var reading = resolve(element)
        if reading.status == .unsupported, let source,
           enableEnhancedAccessibility(source), let refreshed = Accessibility.focusedElement(),
           SecureInput.isPassword(refreshed) == false, SecureInput.status() == .allowed,
           source == Accessibility.frontmostApplication {
            element = refreshed; reading = resolve(element)
        }
        guard reading.status == .success, let text = reading.text else { return result(reading.status) }
        var rect: CGRect?
        if let range = Accessibility.attribute(kAXSelectedTextRangeAttribute, of: element) {
            var bounds: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success,
               let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() {
                let value = bounds as! AXValue
                var candidate = CGRect.zero
                if AXValueGetType(value) == .cgRect, AXValueGetValue(value, .cgRect, &candidate),
                   candidate.width > 0, candidate.height > 0 { rect = candidate }
            }
        }
        guard SecureInput.status() == .allowed else { return result(.secureInput) }
        guard source == Accessibility.frontmostApplication else { return result(.unsupported) }
        return result(.success, text, rect)
    }
    private static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let raw = Accessibility.attribute(kAXSelectedTextRangeAttribute, of: element),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = raw as! AXValue
        var range = CFRange()
        guard AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range) else { return nil }
        return range
    }

    private static func parameterizedText(_ element: AXUIElement, range: CFRange, attributed: Bool) -> String? {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else { return nil }
        var output: CFTypeRef?
        let name = attributed ? kAXAttributedStringForRangeParameterizedAttribute : kAXStringForRangeParameterizedAttribute
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, value, &output) == .success else { return nil }
        return attributed ? (output as? NSAttributedString)?.string : output as? String
    }

    /// Chromium exposes richer selection attributes after this supported, per-process AX flag.
    /// Never enable it to bypass an uninspectable/password focus, and never traverse a whole page.
    private static func enableEnhancedAccessibility(_ source: Accessibility.Application) -> Bool {
        guard ["com.google.Chrome", "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"].contains(source.bundleID ?? ""),
              source == Accessibility.frontmostApplication, SecureInput.status() == .allowed else { return false }
        let app = AXUIElementCreateApplication(source.pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        let name = "AXEnhancedUserInterface" as CFString
        if Accessibility.attribute(name as String, of: app) as? Bool == true { return false }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(app, name, &settable) == .success, settable.boolValue else { return false }
        return AXUIElementSetAttributeValue(app, name, kCFBooleanTrue) == .success
    }

    static func classify(text: String?, selectionLength: Int?) -> Status {
        guard let text else { return .unsupported }
        if !text.isEmpty { return .success }
        return selectionLength == 0 ? .empty : .unsupported
    }

}

/// Bounded selection-only fallback. AXValue/full document text is intentionally never requested.
struct SelectionTextResolution {
    let status: SelectionReader.Status
    let text: String?
    @MainActor static func read(readable: () -> Bool, selected: () -> String?, range: () -> CFRange?,
                               string: (CFRange) -> String?, attributed: (CFRange) -> String?) -> Self {
        guard readable() else { return .init(status: .secureInput, text: nil) }
        let direct = selected()
        guard readable() else { return .init(status: .secureInput, text: nil) }
        if let direct, !direct.isEmpty { return .init(status: .success, text: direct) }
        let selection = range()
        guard readable() else { return .init(status: .secureInput, text: nil) }
        guard let selection, selection.location >= 0, selection.length >= 0,
              selection.length <= 65_536, selection.location <= Int.max - selection.length else {
            return .init(status: .unsupported, text: nil)
        }
        if selection.length == 0 { return .init(status: .empty, text: nil) }
        for useAttributed in [false, true] {
            guard readable() else { return .init(status: .secureInput, text: nil) }
            let value = useAttributed ? attributed(selection) : string(selection)
            guard readable() else { return .init(status: .secureInput, text: nil) }
            // Range APIs use UTF-16. Reject a provider returning the whole document instead.
            if let value, !value.isEmpty, value.utf16.count == selection.length {
                return .init(status: .success, text: value)
            }
        }
        return .init(status: .unsupported, text: nil)
    }
}
