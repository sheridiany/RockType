#if DEBUG
import SwiftUI

@MainActor enum WordLookupGallery {
    // Authored examples, not copied from a system dictionary or user selection.
    static let sample = WordLookup.Definition(term: "clarity", pronunciation: "/ˈklærəti/", senses: [
        .init(partOfSpeech: "名词", meaning: "表达清楚、容易理解的状态。"),
        .init(partOfSpeech: "名词", meaning: "思路明确，能看清问题中的重要部分。")])
    static let phrase = WordLookup.Definition(term: "in focus", pronunciation: nil, senses: [
        .init(partOfSpeech: nil, meaning: "清晰可见；正在受到关注。")])
    static let entries: [GalleryEntry] = [
        GalleryEntry(surface: "word-lookup", state: "word", title: "本机词典 · 单词") {
            AnyView(WordDefinitionCard(definition: sample).padding(Tokens.Space.lg).frame(width: Tokens.Size.resultWidth))
        },
        GalleryEntry(surface: "word-lookup", state: "phrase", title: "本机词典 · 短词组") {
            AnyView(WordDefinitionCard(definition: phrase).padding(Tokens.Space.lg).frame(width: Tokens.Size.resultWidth))
        }
    ]
}
#endif
