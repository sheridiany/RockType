import XCTest
import RoarkTCore
@testable import RoarkTPlatform

final class KeychainTests: XCTestCase {
    @MainActor func testIsolatedRoundTrip() throws {
        let service = Identifiers.keychainService + ".tests." + UUID().uuidString
        let keychain = Keychain(service: service, checkReadable: {})
        let account = "synthetic-test"
        defer { XCTAssertNoThrow(try keychain.delete(account: account)) }
        XCTAssertFalse(try keychain.exists(account: account))
        XCTAssertNil(try keychain.get(account: account))
        try keychain.set("synthetic-value-1", account: account)
        XCTAssertTrue(try keychain.exists(account: account))
        try keychain.set("synthetic-value-2", account: account)
        XCTAssertEqual(try keychain.get(account: account), "synthetic-value-2")
        try keychain.delete(account: account)
        XCTAssertFalse(try keychain.exists(account: account))
        XCTAssertNil(try keychain.get(account: account))
        try keychain.delete(account: account)
    }

    @MainActor func testProtectedReadsAreDenied() {
        let keychain = Keychain(service: Identifiers.keychainService + ".tests", checkReadable: { throw PlatformReadError.secureInput })
        XCTAssertThrowsError(try keychain.get(account: "synthetic")) { XCTAssertEqual($0 as? PlatformReadError, .secureInput) }
        XCTAssertThrowsError(try keychain.exists(account: "synthetic")) { XCTAssertEqual($0 as? PlatformReadError, .secureInput) }
    }
}
