import Foundation

/// Best-effort preference evidence only, never an installation gate or a source of writes.
public struct InputSourcePreferenceEvidence: Codable, Equatable, Sendable {
    public let listReadable: Bool
    public let parentEnabled: Bool
    public let pinyinEnabled: Bool
    public let flypyEnabled: Bool

    public init(preference: Any?) {
        let entries = preference as? [[String: Any]]
        listReadable = entries != nil
        let own = (entries ?? []).filter { $0["Bundle ID"] as? String == Identifiers.inputMethodBundleID }
        parentEnabled = own.contains { $0["InputSourceKind"] as? String == "Keyboard Input Method" }
        func mode(_ id: String) -> Bool {
            own.contains { $0["InputSourceKind"] as? String == "Input Mode" && $0["Input Mode"] as? String == id }
        }
        pinyinEnabled = mode(Identifiers.pinyinInputSourceID)
        flypyEnabled = mode(Identifiers.flypyInputSourceID)
    }
}

/// Public TIS state, independent of undocumented preference storage layouts.
public struct InputSourceEnablementState: Codable, Equatable, Sendable {
    public let registeredIDs: [String]
    public let enabledIDs: [String]
    public let selectableIDs: [String]
    public let verificationPassed: Bool

    public init(registered: Set<String>, enabled: Set<String>, selectable: Set<String>) {
        registeredIDs = registered.sorted()
        enabledIDs = enabled.sorted()
        selectableIDs = selectable.sorted()
        verificationPassed = Set(InputSourceEnablement.requiredIDs).isSubset(of: registered)
            && Set(InputSourceEnablement.requiredIDs).isSubset(of: enabled)
            && selectable.contains(Identifiers.pinyinInputSourceID)
    }
}

/// Installer policy. A successful API call must be followed by a fresh TIS verification.
public enum InputSourceEnablement {
    public enum Failure: Error { case registrationIncomplete, enablementUnconfirmed }
    public static let requiredIDs = [Identifiers.inputMethodBundleID, Identifiers.pinyinInputSourceID]
    public static let registeredIDs = requiredIDs + [Identifiers.flypyInputSourceID]

    public static func ensure(
        state: () -> InputSourceEnablementState,
        register: () throws -> Void, enable: (String) throws -> Void,
        verifyFresh: () -> Bool
    ) throws {
        if !Set(registeredIDs).isSubset(of: Set(state().registeredIDs)) {
            try register()
            guard Set(registeredIDs).isSubset(of: Set(state().registeredIDs)) else { throw Failure.registrationIncomplete }
        }
        for id in requiredIDs where !state().enabledIDs.contains(id) { try enable(id) }
        guard verifyFresh() else { throw Failure.enablementUnconfirmed }
    }
}
