import Foundation

/// HIToolbox preference metadata only; never contains or writes input text.
public struct PersistentInputSourceState: Codable, Equatable, Sendable {
    public let listReadable: Bool
    public let parentEnabled: Bool
    public let pinyinEnabled: Bool
    public let flypyEnabled: Bool
    public var requiredSourcesEnabled: Bool { listReadable && parentEnabled && pinyinEnabled }

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

/// Installer policy. API success alone is not proof of durable enablement.
public enum InputSourceEnablement {
    public enum Failure: Error { case registrationIncomplete, persistenceUnconfirmed }
    public static let requiredIDs = [Identifiers.inputMethodBundleID, Identifiers.pinyinInputSourceID]
    public static let registeredIDs = requiredIDs + [Identifiers.flypyInputSourceID]

    public static func ensure(
        persistent: PersistentInputSourceState,
        registered: () -> Set<String>, enabled: () -> Set<String>,
        register: () throws -> Void, enable: (String) throws -> Void,
        verifyFresh: () -> Bool
    ) throws {
        if !Set(registeredIDs).isSubset(of: registered()) {
            try register()
            guard Set(registeredIDs).isSubset(of: registered()) else { throw Failure.registrationIncomplete }
        }
        for (id, persisted) in zip(requiredIDs, [persistent.parentEnabled, persistent.pinyinEnabled]) {
            if !persisted || !enabled().contains(id) { try enable(id) }
        }
        guard verifyFresh() else { throw Failure.persistenceUnconfirmed }
    }
}
