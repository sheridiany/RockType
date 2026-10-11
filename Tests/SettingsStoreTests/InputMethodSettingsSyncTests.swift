import Foundation
import Testing
import RoarkTCore
@testable import RoarkTApp

@MainActor @Test func successfulPersistenceNotifiesAndOnlyChangedPatchesRedeploy() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = SettingsPersistence(fileURL: directory.appendingPathComponent("settings.json"))
    let writer = RimeSettingsPatchWriter(directory: directory.appendingPathComponent("Rime"))
    var signals: [Notification.Name] = []
    var diskSnapshots: [InputMethodPreferences] = []
    let sync = InputMethodSettingsSynchronizer(writer: writer) {
        signals.append($0)
        diskSnapshots.append(InputMethodPreferences.load(from: persistence.fileURL))
    }
    let store = SettingsStore(persistence: persistence, inputMethodSync: sync)
    store.settings.input.candidateTranslation = false
    #expect(signals.isEmpty, "No signal until successful persistence")
    store.flush()
    #expect(signals == [InputMethodSettingsNotification.changed, InputMethodSettingsNotification.redeploy])
    #expect(signals.filter { $0 == InputMethodSettingsNotification.redeploy }.count == 1)
    #expect(diskSnapshots.allSatisfy { !$0.input.candidateTranslation })
    signals.removeAll()
    store.settings.general.showBeijingTime = true
    store.flush()
    #expect(signals == [InputMethodSettingsNotification.changed], "Unrelated settings must not rebuild Rime")
    signals.removeAll()
    store.settings.input.fuzzyPinyin = false
    store.flush()
    #expect(signals.filter { $0 == InputMethodSettingsNotification.redeploy }.count == 1)
    #expect(store.inputMethodSyncMessage == nil)
    signals.removeAll()
    store.settings.schemaVersion = 99
    store.flush()
    #expect(signals.isEmpty && store.persistenceError != nil)
}

@MainActor @Test func customFileConflictIsVisibleButRuntimeSettingsStillNotify() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let rime = directory.appendingPathComponent("Rime")
    try FileManager.default.createDirectory(at: rime, withIntermediateDirectories: true)
    let userFile = rime.appendingPathComponent("roarkt.custom.yaml")
    let data = Data("patch: {}\n".utf8)
    try data.write(to: userFile)
    var signals: [Notification.Name] = []
    let sync = InputMethodSettingsSynchronizer(writer: .init(directory: rime)) { signals.append($0) }
    let store = SettingsStore(persistence: .init(fileURL: directory.appendingPathComponent("settings.json")), inputMethodSync: sync)
    store.flush()
    #expect(store.inputMethodSyncMessage?.contains("roarkt.custom.yaml") == true)
    #expect(store.persistenceError == nil)
    #expect(signals == [InputMethodSettingsNotification.changed])
    #expect(try Data(contentsOf: userFile) == data)
    try FileManager.default.removeItem(at: userFile)
    store.flush()
    #expect(store.inputMethodSyncMessage == nil)
    #expect(signals.contains(InputMethodSettingsNotification.redeploy))
}

@MainActor @Test func launchRegeneratesOutdatedAppOwnedPatches() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = SettingsPersistence(fileURL: directory.appendingPathComponent("settings.json"))
    try persistence.save(.defaults)
    let rime = directory.appendingPathComponent("Rime")
    try FileManager.default.createDirectory(at: rime, withIntermediateDirectories: true)
    let file = rime.appendingPathComponent("roarkt.custom.yaml")
    try Data((RimeSettingsPatch.marker + "\npatch:\n  __include: roarkt_personal.patch:/patch?\n").utf8).write(to: file)
    var signals: [Notification.Name] = []
    let sync = InputMethodSettingsSynchronizer(writer: .init(directory: rime)) { signals.append($0) }
    _ = SettingsStore(persistence: persistence, inputMethodSync: sync)
    #expect(try String(contentsOf: file, encoding: .utf8) == RimeSettingsPatch.yaml(for: .pinyin, settings: AppSettings.defaults.input))
    #expect(signals.contains(InputMethodSettingsNotification.redeploy))
    signals.removeAll()
    _ = SettingsStore(persistence: persistence, inputMethodSync: sync)
    #expect(!signals.contains(InputMethodSettingsNotification.redeploy), "Unchanged patches must not rebuild Rime")
}
