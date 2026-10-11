import Foundation
import Testing
@testable import RoarkTCore

/// Exercise librime's patch compiler, not just our YAML strings. All files live in a fresh temp tree.
@Test func generatedSettingsPatchesDeployAgainstShippedSchemas() throws {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let runtime = repo.appendingPathComponent("InputMethod")
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("roarkt-settings-deploy-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let fm = FileManager.default
    let shared = temporary.appendingPathComponent("shared"), user = temporary.appendingPathComponent("user")
    let build = temporary.appendingPathComponent("build"), bin = temporary.appendingPathComponent("bin")
    for directory in [shared, user, build, bin] { try fm.createDirectory(at: directory, withIntermediateDirectories: true) }
    let deployer = bin.appendingPathComponent("rime_deployer")
    try fm.copyItem(at: runtime.appendingPathComponent("bin/rime_deployer"), to: deployer)
    try fm.createSymbolicLink(at: temporary.appendingPathComponent("Frameworks"), withDestinationURL: runtime.appendingPathComponent("lib"))
    for name in ["default.yaml", "key_bindings.yaml", "punctuation.yaml", "symbols.yaml", "pinyin.yaml", "luna_pinyin.dict.yaml", "essay.txt", "zh-hant-t-essay-bgw.gram"] {
        try fm.copyItem(at: runtime.appendingPathComponent("data/plum/" + name), to: shared.appendingPathComponent(name))
    }
    try fm.copyItem(at: runtime.appendingPathComponent("data/opencc"), to: shared.appendingPathComponent("opencc"))
    let rime = repo.appendingPathComponent("Rime")
    try fm.copyItem(at: rime.appendingPathComponent("lua"), to: shared.appendingPathComponent("lua"))
    for file in try fm.contentsOfDirectory(at: rime, includingPropertiesForKeys: nil) where file.pathExtension == "yaml" {
        try fm.copyItem(at: file, to: shared.appendingPathComponent(file.lastPathComponent))
    }
    try fm.copyItem(at: shared.appendingPathComponent("default.custom.yaml"), to: user.appendingPathComponent("default.custom.yaml"))
    let writer = RimeSettingsPatchWriter(directory: user)
    func deploy(_ settings: InputSettings) throws -> [String] {
        _ = try writer.write(settings)
        let process = Process()
        process.executableURL = deployer
        process.arguments = ["--build", user.path, shared.path, build.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return try ["roarkt.schema.yaml", "roarkt_flypy.schema.yaml"].map {
            try String(contentsOf: build.appendingPathComponent($0), encoding: .utf8)
        }
    }
    func algebra(_ yaml: String) -> [String] {
        let lines = yaml.components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: "speller:"),
              let end = lines[(start + 1)...].firstIndex(where: { !$0.hasPrefix(" ") && !$0.isEmpty }) else { return [] }
        return lines[start..<end].filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }
    }
    let baseline = try deploy(InputSettings())
    var disabled = InputSettings()
    disabled.fuzzyPinyin = false; disabled.abbreviatedPinyin = false; disabled.spellingCorrection = false
    disabled.englishCompletion = false; disabled.shiftTogglesLanguage = false
    let changed = try deploy(disabled)
    let pinyin = algebra(changed[0]), flypy = algebra(changed[1])
    #expect(pinyin.count == 19 && pinyin.count == algebra(baseline[0]).count)
    #expect(pinyin.prefix(18).allSatisfy { $0.contains("xform/^(.+)$/$1/") })
    #expect(pinyin.last == algebra(baseline[0]).last)
    #expect(flypy.count == algebra(baseline[1]).count && flypy.count > 7)
    #expect(flypy[1...6].allSatisfy { $0.contains("xform/^(.+)$/$1/") })
    #expect(flypy.first == algebra(baseline[1]).first)
    #expect(Array(flypy.dropFirst(7)) == Array(algebra(baseline[1]).dropFirst(7)))
    for yaml in changed {
        #expect(yaml.contains("Shift_L: noop") && yaml.contains("Shift_R: noop"))
        let english = yaml.components(separatedBy: "english:\n").last?.components(separatedBy: "\nengine:").first ?? ""
        #expect(english.contains("enable_completion: false"))
    }
    #expect(try deploy(InputSettings()).map(algebra) == baseline.map(algebra), "Re-enabling restores inherited algebra")
}
