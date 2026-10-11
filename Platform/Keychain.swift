import Foundation
import Security
import LocalAuthentication
import RoarkTCore

@MainActor public struct Keychain {
    public struct Failure: Error, Equatable, Sendable {
        public let status: OSStatus
    }
    public let service: String
    private let checkReadable: @MainActor () throws -> Void

    public init(service: String = Identifiers.keychainService) {
        self.service = service
        self.checkReadable = { try SecureInput.requireReadable() }
    }
    init(service: String, checkReadable: @escaping @MainActor () throws -> Void) {
        self.service = service; self.checkReadable = checkReadable
    }

    private func query(_ account: String) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: account, kSecUseAuthenticationContext as String: context]
    }

    public func set(_ secret: String, account: String) throws {
        let data = Data(secret.utf8)
        var status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query(account)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    public func get(account: String) throws -> String? {
        try checkReadable()
        var attributes = query(account)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        guard let data = value as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw Failure(status: errSecDecode)
        }
        try checkReadable()
        return secret
    }

    /// Queries metadata only; never permits an authorization dialog.
    public func exists(account: String) throws -> Bool {
        try checkReadable()
        var attributes = query(account)
        attributes[kSecReturnAttributes as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(attributes as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw Failure(status: status) }
        return true
    }

    public func delete(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}
