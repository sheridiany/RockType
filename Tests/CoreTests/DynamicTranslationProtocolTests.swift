import Testing
@testable import RoarkTCore

@Test func translationDirectionsHaveStableWireValues() {
    #expect(DynamicTranslationDirection.chineseToEnglish.rawValue == "zh-en")
    #expect(DynamicTranslationDirection.englishToChinese.rawValue == "en-zh")
}

@Test func translationSkipsPunctuationOnlyCandidates() {
    #expect(DynamicTranslationPolicy.shouldTranslate("我不知道"))
    #expect(DynamicTranslationPolicy.shouldTranslate("hello"))
    #expect(!DynamicTranslationPolicy.shouldTranslate("。"))
    #expect(!DynamicTranslationPolicy.shouldTranslate("!? 123"))
}
