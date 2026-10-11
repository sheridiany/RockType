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
        guard let element = Accessibility.focusedElement(), let password = SecureInput.isPassword(element) else { return result(.unsupported) }
        guard !password, !SecureInput.isSecureInputActive() else { return result(.secureInput) }
        guard let text = Accessibility.attribute(kAXSelectedTextAttribute, of: element) as? String else { return result(.unsupported) }
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
        if text.isEmpty {
            // Some web/Electron controls expose an empty string despite a selection.
            // Only a positively reported zero-length range proves that nothing is selected.
            if let range = Accessibility.attribute(kAXSelectedTextRangeAttribute, of: element),
               CFGetTypeID(range) == AXValueGetTypeID() {
                let value = range as! AXValue
                var selected = CFRange()
                if AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &selected), selected.length >= 0 {
                    return result(classify(text: text, selectionLength: selected.length))
                }
            }
            return result(classify(text: text, selectionLength: nil))
        }
        return result(.success, text, rect)
    }
    static func classify(text: String?, selectionLength: Int?) -> Status {
        guard let text else { return .unsupported }
        if !text.isEmpty { return .success }
        return selectionLength == 0 ? .empty : .unsupported
    }

}
