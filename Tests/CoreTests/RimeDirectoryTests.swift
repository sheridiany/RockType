import Foundation
import Testing
import RoarkTCore

@Test func privateRimeDirectoryAndFirstLaunchMetadata() throws {
    let fm = FileManager.default
    let home = fm.temporaryDirectory.appendingPathComponent("rime home ' " + UUID().uuidString)
    defer { try? fm.removeItem(at: home) }
    let directory = Identifiers.rimeUserDirectory(home: home)
    #expect(directory.path == home.appendingPathComponent("Library/Application Support/" + Identifiers.applicationSupportFolder + "/Rime").path)
    #expect(directory != home.appendingPathComponent("Library/Rime"))
    #expect(RimeSettingsPatchWriter().directory == Identifiers.rimeUserDirectory())
    try Identifiers.prepareRimeDirectory(home: home)
    let installation = directory.appendingPathComponent("installation.yaml")
    let metadata = try String(contentsOf: installation, encoding: .utf8)
    let scalar = String(metadata.dropFirst("sync_dir: ".count)).trimmingCharacters(in: .newlines)
    #expect(try JSONDecoder().decode(String.self, from: Data(scalar.utf8)) == directory.appendingPathComponent("sync").path)
    try Identifiers.prepareRimeDirectory(home: home)
    #expect(try String(contentsOf: installation, encoding: .utf8) == metadata)
    _ = try RimeSettingsPatchWriter(directory: directory).write(.init())
    #expect(fm.fileExists(atPath: directory.appendingPathComponent("roarkt.custom.yaml").path))
    #expect(!fm.fileExists(atPath: home.appendingPathComponent("Library/Rime").path))
}
