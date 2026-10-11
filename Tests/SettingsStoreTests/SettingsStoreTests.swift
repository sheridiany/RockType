import Foundation
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor @Test func storeNotifiesImmediatelyPersistsAndRestores() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = SettingsPersistence(fileURL: directory.appendingPathComponent("settings.json"))
    let store = SettingsStore(persistence: persistence)
    let observed = NotificationCount()
    let token = NotificationCenter.default.addObserver(forName: SettingsStore.didChange, object: store, queue: nil) { _ in
        observed.increment()
    }
    defer { NotificationCenter.default.removeObserver(token) }
    store.settings.general.showBeijingTime = true
    #expect(observed.value == 1)
    #expect(store.settings.general.showBeijingTime)
    try await Task.sleep(for: .milliseconds(290))
    #expect(try persistence.load().settings.general.showBeijingTime)
    store.settings.general.launchAtLogin = true
    store.flush()
    #expect(store.persistenceError == nil)
    #expect(SettingsStore(persistence: persistence).settings == store.settings)
}

private final class NotificationCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

@MainActor @Test func storeDoesNotOverwriteUnreadableOriginal() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    // A directory at the file path produces a read error, not a missing-file recovery.
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = SettingsStore(persistence: SettingsPersistence(fileURL: directory))
    #expect(store.persistenceError != nil)
    store.settings.general.showBeijingTime = true
    store.flush()
    #expect(store.persistenceError != nil)
    let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    #expect(attributes[.type] as? FileAttributeType == .typeDirectory)
}
