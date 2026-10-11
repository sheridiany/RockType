import Foundation
import Testing
@testable import RoarkTCore

@Test func voiceCleanerRemovesOnlyDelimitedFillers() {
    for (input, expected) in [
        ("嗯，啊，今天出发", "今天出发。"),
        ("呃。额，那个，就是说，我们走吧", "我们走吧。"),
        ("今天，嗯，出发", "今天，出发。"),
        ("嗯", ""), ("那个，", ""),
        ("那个方案可行", "那个方案可行。"),
        ("就是说服他", "就是说服他。"),
        ("啊哈，这是语气词啊", "啊哈，这是语气词啊。"),
        ("嗯嗯可以", "嗯嗯可以。"),
        ("余额不足", "余额不足。"),
        ("他说“那个”", "他说“那个”"),
        ("  hello   world  ", "hello world"),
        ("用  Swift\t 6 写代码", "用 Swift 6 写代码。"),
        ("第一行\n第二行", "第一行\n第二行。"),
        ("完成！", "完成！"), ("等等……", "等等……"),
        ("真的？", "真的？"), ("保留，", "保留，"),
        (" \n\t", "")
    ] {
        #expect(VoiceTextCleaner.clean(input) == expected)
        #expect(VoiceTextCleaner.clean(expected) == expected)
    }
}

@Test func voiceLocalCleanupDefaultsAndPersists() throws {
    #expect(VoiceSettings().cleanUpLocally)
    let existing = Data(#"{"model":"1.7B-8bit","automaticallyPrepareModel":true,"polishWithAI":true}"#.utf8)
    let decoded = try JSONDecoder().decode(VoiceSettings.self, from: existing)
    #expect(decoded.cleanUpLocally && decoded.automaticallyPrepareModel && decoded.polishWithAI)
    #expect(decoded.model == .large)
    var settings = VoiceSettings()
    settings.cleanUpLocally = false
    #expect(try JSONDecoder().decode(VoiceSettings.self, from: JSONEncoder().encode(settings)) == settings)
}
