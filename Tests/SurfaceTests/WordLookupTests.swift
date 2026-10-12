import AppKit
import SwiftUI
import Testing
@testable import RoarkTApp

@Suite(.serialized) @MainActor struct WordLookupTests {
    @Test func shortEnglishOnlyAndBoundedInput() {
        for (raw, expected) in [("  Clarity  ", "Clarity"), ("in\t  focus", "in focus"), ("well‑known", "well-known"),
                                ("state-of-the-art", "state-of-the-art"), ("a little bit", "a little bit")] {
            #expect(WordLookup.normalizedTerm(raw) == expected)
        }
        for raw in ["", " ", "one two three four", "中文", "word2", "-word", "word-", "a--b", "can't", "a/b", "<b>word</b>",
                    "one\ntwo", "one\u{0}two", String(repeating: "a", count: 97), String(repeating: " ", count: 257)] {
            #expect(WordLookup.normalizedTerm(raw) == nil)
        }
    }

    @Test func parsesExplicitIPAHeadingsAndFirstThreeSenses() throws {
        // Synthetic text in the format returned by DictionaryServices; not a vendor entry.
        let raw = "clarity clar·i·ty | ˈklærəti | noun [mass noun] 1 synthetic first meaning: synthetic example. 2 synthetic second meaning • synthetic related meaning 3 omitted meaning ORIGIN synthetic history"
        let result = try #require(WordDefinitionParser.parse(raw, term: "clarity"))
        #expect(result.pronunciation == "/ˈklærəti/")
        #expect(result.senses.map(\.meaning) == ["synthetic first meaning", "synthetic second meaning", "synthetic related meaning"])
        #expect(result.senses.allSatisfy { $0.partOfSpeech == "名词" })
        let bilingual = try #require(WordDefinitionParser.parse("clear /klɪə/ adj. 清晰的\nv. 清理；使通畅", term: "clear"))
        #expect(bilingual.senses.map(\.partOfSpeech) == ["形容词", "动词"])
        #expect(bilingual.senses.map(\.meaning) == ["清晰的", "清理；使通畅"])
    }

    @Test func unknownFormatIsConservativeAndUnavailableIsNil() throws {
        let plain = try #require(WordDefinitionParser.parse("in focus 清晰可见；受到关注", term: "in focus"))
        #expect(plain.pronunciation == nil && plain.senses[0].partOfSpeech == nil)
        #expect(plain.senses[0].meaning == "清晰可见；受到关注")
        let notes = try #require(WordDefinitionParser.parse("word [mass noun] synthetic meaning", term: "word"))
        #expect(notes.pronunciation == nil)
        #expect(notes.senses[0].meaning == "synthetic meaning")
        let number = try #require(WordDefinitionParser.parse("word noun a set of 2 synthetic parts", term: "word"))
        #expect(number.senses.map(\.meaning) == ["a set of 2 synthetic parts"])
        #expect(WordDefinitionParser.parse("word", term: "word") == nil)
        #expect(WordDefinitionParser.parse("  ", term: "word") == nil)
        #expect(WordDefinitionParser.parse(String(repeating: "x", count: 65_537), term: "word") == nil)
        let long = try #require(WordDefinitionParser.parse(String(repeating: "字", count: 1000), term: "word"))
        #expect(long.senses[0].meaning.count == 260 && long.senses[0].meaning.hasSuffix("…"))
    }

    @Test func protectionAndInvalidInputNeverCallProvider() async {
        let blocked = WordLookup(allowed: { false }, provider: { _ in Issue.record("Protected query reached provider"); return nil })
        #expect(await blocked.lookup("clarity") == nil)
        let invalid = WordLookup(allowed: { true }, provider: { _ in Issue.record("Invalid query reached provider"); return nil })
        #expect(await invalid.lookup("This is not a short phrase") == nil)
        let unavailable = WordLookup(allowed: { true }, provider: { _ in nil })
        #expect(await unavailable.lookup("clarity") == nil)
    }

    @Test func protectedOrCancelledLateResultsAreDiscarded() async {
        for cancel in [false, true] {
            var readable = true
            let (entered, enteredContinuation) = AsyncStream<Void>.makeStream()
            let (replies, replyContinuation) = AsyncStream<String>.makeStream()
            let lookup = WordLookup(allowed: { readable }, provider: { _ in
                enteredContinuation.yield(())
                for await reply in replies { return reply }
                return nil
            })
            let pending = Task { await lookup.lookup("clarity") }
            var iterator = entered.makeAsyncIterator()
            _ = await iterator.next()
            if cancel { pending.cancel() } else { readable = false }
            replyContinuation.yield("clarity noun synthetic meaning")
            replyContinuation.finish(); enteredContinuation.finish()
            #expect(await pending.value == nil)
        }
    }

    @Test func realLocalDictionaryMayBeUnavailableButNeverNeedsNetwork() async {
        // Explicit synthetic lookup, no selected text or system preference changes.
        let result = await WordLookup(allowed: { true }).lookup("serendipity")
        if let result {
            #expect(result.term == "serendipity")
            #expect((1...3).contains(result.senses.count))
            #expect(result.senses.allSatisfy { !$0.meaning.isEmpty })
        }
    }

    @Test func renderWordAndPhraseLightDarkAndNarrow() throws {
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/t2")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, definition) in [("word", WordLookupGallery.sample), ("phrase", WordLookupGallery.phrase)] {
            for dark in [false, true] {
                for width in [320.0, 420.0] {
                    let p = Tokens.Palette(dark: dark)
                    let view = WordDefinitionCard(definition: definition).padding(Tokens.Space.lg)
                        .frame(width: width).background(p.canvas).environment(\.colorScheme, dark ? .dark : .light)
                    let renderer = ImageRenderer(content: view.fixedSize())
                    renderer.scale = 2
                    let image = try #require(renderer.cgImage)
                    let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                    try png.write(to: output.appendingPathComponent("\(name)-\(Int(width))-\(dark ? "dark" : "light").png"))
                    #expect(image.width == Int(width) * 2)
                    #expect(image.height > 150 && image.height < 800)
                }
            }
        }
    }
}
