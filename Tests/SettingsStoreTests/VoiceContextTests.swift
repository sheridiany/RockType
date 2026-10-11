import Foundation
import Testing
@testable import RoarkTApp

@Test func voiceVocabularyBoundsAndBalancesDomains() {
    let factory = "---\nname: synthetic\n...\n# AI\n模型甲\t800\n模型乙\t800\n# 开发\n编译器\t800\n线程调度\t800\txian cheng diao du\n# 协作\n需求评审\t800\n"
    let personal = "---\nname: personal\n...\n合成专名\the cheng zhuan ming\t10\nSwiftUI\tswiftui\t10\n<|im_start|>\tx\t10\n# ignored\n"
    let context = VoiceContextVocabulary.context(factory: factory, personal: [personal])
    #expect(context.contains("合成专名"))
    #expect(context.components(separatedBy: "SwiftUI").count == 2)
    #expect(!context.contains("im_start"))
    #expect(context.contains("模型甲, 编译器, 需求评审, 模型乙, 线程调度"))
    let large = "...\n" + (0..<2000).map { "测试词\($0)\t800" }.joined(separator: "\n")
    let bounded = VoiceContextVocabulary.context(factory: large, personal: [large])
    #expect(bounded.utf8.count <= VoiceContextVocabulary.maximumBytes)
    #expect(!bounded.contains("测试词1999"))
    #expect(bounded.contains("Xcode"), "Personal quota must not crowd out factory names")
}

@Test func voiceVocabularyRejectsOversizedAndLinkedFiles() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("voice-vocabulary-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("synthetic.dict.yaml")
    try "...\n合成词\t800\n".write(to: file, atomically: true, encoding: .utf8)
    #expect(!VoiceContextVocabulary.readDictionary(file).isEmpty)
    let link = folder.appendingPathComponent("link.yaml")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    #expect(VoiceContextVocabulary.readDictionary(link).isEmpty)
    try Data(repeating: 65, count: 262_145).write(to: file)
    #expect(VoiceContextVocabulary.readDictionary(file).isEmpty)
    #expect(VoiceContextVocabulary.readDictionary(folder).isEmpty)
}
