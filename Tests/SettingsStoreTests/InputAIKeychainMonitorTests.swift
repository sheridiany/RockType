import Foundation
import Testing
import RoarkTCore
import RoarkTPlatform
@testable import RoarkTApp

@MainActor private final class KeychainEvents { var count = 0 }

@Test @MainActor func inputAIKeychainMonitorReceivesIsolatedKeyEdits() async throws {
    let monitor = InputAIKeychainMonitor()
    let events = KeychainEvents()
    let observer = NotificationCenter.default.addObserver(forName: InputAIKeychainMonitor.changed, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { events.count += 1 }
    }
    let keychain = Keychain(service: Identifiers.keychainService + ".tests." + UUID().uuidString)
    let account = "synthetic-input-ai"
    defer {
        monitor.stop(); NotificationCenter.default.removeObserver(observer)
        try? keychain.delete(account: account)
    }
    #expect(monitor.start())
    try keychain.set("synthetic-monitor-one", account: account)
    let deadline = ContinuousClock.now + .seconds(3)
    while events.count == 0, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(events.count > 0)
    let before = events.count
    try keychain.set("synthetic-monitor-two", account: account)
    let updated = ContinuousClock.now + .seconds(3)
    while events.count == before, ContinuousClock.now < updated {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(events.count > before)
    let beforeDelete = events.count
    try keychain.delete(account: account)
    let deleted = ContinuousClock.now + .seconds(3)
    while events.count == beforeDelete, ContinuousClock.now < deleted {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(events.count > beforeDelete)
}
