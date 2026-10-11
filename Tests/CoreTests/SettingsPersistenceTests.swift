import Foundation
import Testing
@testable import RoarkTCore

@Test func settingsPersistenceMissingSaveReloadAndPermissions() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = SettingsPersistence(fileURL: directory.appendingPathComponent("settings.json"))
    #expect(try persistence.load().status == .missing)
    var settings = AppSettings()
    settings.general.showBeijingTime = true
    try persistence.save(settings)
    #expect(try persistence.load().settings == settings)
    #expect(try persistence.load().status == .loaded)
    let attributes = try FileManager.default.attributesOfItem(atPath: persistence.fileURL.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test(arguments: [Data("{".utf8), Data("{}".utf8), Data("null".utf8)])
func settingsCorruptionIsPreservedBeforeRecovery(data: Data) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let persistence = SettingsPersistence(fileURL: directory.appendingPathComponent("settings.json"))
    try data.write(to: persistence.fileURL)
    let loaded = try persistence.load()
    #expect(loaded.settings == .defaults)
    guard case .recovered(let backup) = loaded.status else { Issue.record("No recovery evidence"); return }
    #expect(backup.lastPathComponent.hasPrefix("settings.json.corrupt-"))
    #expect(try Data(contentsOf: backup) == data)
    #expect(try persistence.load().status == .loaded)
}

@Test func invalidSettingsNeverReplaceValidFile() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = SettingsPersistence(fileURL: directory.appendingPathComponent("settings.json"))
    try persistence.save(.defaults)
    var settings = AppSettings()
    settings.selection.windowOpacity = -1
    #expect(throws: SettingsPersistence.Failure.invalidValues) { try persistence.save(settings) }
    #expect(try persistence.load().settings == .defaults)
    settings = .defaults
    settings.schemaVersion = 99
    #expect(throws: SettingsPersistence.Failure.unsupportedSchema(99)) { try persistence.save(settings) }
}
