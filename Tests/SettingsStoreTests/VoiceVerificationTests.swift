import Foundation
import Testing
@testable import RoarkTApp

/// The full SHA-256 runs once; later loads only compare file stamps, and any change re-arms it.
@Test func modelVerificationStampSkipsRehashUntilFilesChange() throws {
    let fm = FileManager.default
    let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: folder) }
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let model = VoiceModel.small
    for file in model.files { try Data("fixture-\(file.name)".utf8).write(to: folder.appendingPathComponent(file.name)) }
    #expect(!VoiceModelVerification.matches(model: model, in: folder), "no record before the first full check")
    VoiceModelVerification.record(model: model, in: folder)
    #expect(VoiceModelVerification.matches(model: model, in: folder))
    // Same size, new content and modification date: must force a full re-hash.
    let changed = folder.appendingPathComponent(model.files[0].name)
    let original = try Data(contentsOf: changed)
    try Data(repeating: 0x41, count: original.count).write(to: changed)
    try fm.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: changed.path)
    #expect(!VoiceModelVerification.matches(model: model, in: folder))
    VoiceModelVerification.record(model: model, in: folder)
    VoiceModelVerification.invalidate(in: folder)
    #expect(!VoiceModelVerification.matches(model: model, in: folder), "a new download clears the record")
}
