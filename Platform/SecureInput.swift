import Carbon
import ApplicationServices

@MainActor public enum SecureInput {
    public enum Status: Sendable { case allowed, secureInput, noPermission, unavailable }

    public static func isSecureInputActive() -> Bool { IsSecureEventInputEnabled() }

    /// nil means the focused element cannot be inspected. Callers must fail closed.
    public static func isFocusedElementPassword() -> Bool? {
        guard Accessibility.isTrusted(), let element = Accessibility.focusedElement() else { return nil }
        return isPassword(element)
    }

    static func isPassword(_ element: AXUIElement) -> Bool? {
        guard let role = Accessibility.attribute(kAXRoleAttribute, of: element) as? String else { return nil }
        let subrole = Accessibility.attribute(kAXSubroleAttribute, of: element) as? String
        return role == kAXSecureTextFieldSubrole || subrole == kAXSecureTextFieldSubrole
    }

    public static func status() -> Status {
        if isSecureInputActive() { return .secureInput }
        guard Accessibility.isTrusted() else { return .noPermission }
        guard let password = isFocusedElementPassword() else { return .unavailable }
        return password ? .secureInput : .allowed
    }

    static func requireReadable() throws {
        switch status() {
        case .allowed: break
        case .secureInput: throw PlatformReadError.secureInput
        case .noPermission: throw PlatformReadError.noPermission
        case .unavailable: throw PlatformReadError.unavailable
        }
    }
}

public enum PlatformReadError: Error, Equatable, Sendable {
    case secureInput, noPermission, unavailable, sourceChanged, clipboardChanged, timeout, busy, writeFailed
}
