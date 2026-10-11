import Foundation
import Security

// No credential, account, or item attributes enter notifications. Reading a key
// does not generate these events, so a refresh cannot recursively trigger itself.
private let inputAIKeychainCallback: SecKeychainCallback = { _, _, _ in
    NotificationCenter.default.post(name: InputAIKeychainMonitor.changed, object: nil)
    return errSecSuccess
}

@MainActor final class InputAIKeychainMonitor {
    nonisolated static let changed = Notification.Name("RoarkTInputAIKeychainChanged")
    private static var observers = 0
    private var active = false
    @discardableResult func start() -> Bool {
        if active { return true }
        if Self.observers == 0 {
            let mask: SecKeychainEventMask = [.addEventMask, .deleteEventMask, .updateEventMask,
                                                .lockEventMask, .unlockEventMask, .defaultChangedEventMask]
            guard SecKeychainAddCallback(inputAIKeychainCallback, mask, nil) == errSecSuccess else { return false }
        }
        Self.observers += 1; active = true; return true
    }
    func stop() {
        guard active else { return }
        active = false; Self.observers -= 1
        if Self.observers == 0 { SecKeychainRemoveCallback(inputAIKeychainCallback) }
    }
    isolated deinit { stop() }
}
