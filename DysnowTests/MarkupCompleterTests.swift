import XCTest
@testable import Dysnow

final class MarkupCompleterTests: XCTestCase {
    private let values: (String) -> [String] = { kind in
        switch kind {
        case "speaker": ["Liam", "Lily", "Fable"]
        case "mood": ["excited", "sad", "calm"]
        case "language": ["English (US)", "German"]
        default: []
        }
    }

    private func completer(_ syntax: MarkupSyntax = .markdown) -> MarkupCompleter {
        MarkupCompleter(syntax: syntax, values: values)
    }

    /// "|" marks the cursor, "«" and "»" a selection.
    private func choices(_ marked: String, _ syntax: MarkupSyntax = .markdown) -> (String, [MarkupCompleter.Choice]) {
        var text = marked
        let start: String.Index, end: String.Index
        if let open = text.firstIndex(of: "«") {
            text.remove(at: open)
            let close = text.firstIndex(of: "»")!
            text.remove(at: close)
            start = text.index(text.startIndex, offsetBy: marked.distance(from: marked.startIndex, to: open))
            end = close
        } else {
            let cursor = text.firstIndex(of: "|")!
            text.remove(at: cursor)
            start = cursor
            end = cursor
        }
        return (text, completer(syntax).choices(in: text, selection: start..<end))
    }

    /// The text after the choice titled `title` is made, with "|" at the
    /// cursor or "«…»" around the selection.
    private func pick(_ title: String, in marked: String, _ syntax: MarkupSyntax = .markdown) -> String? {
        let (text, choices) = choices(marked, syntax)
        guard let choice = choices.first(where: { $0.title == title }) else { return nil }
        let (edited, selection) = choice.edit.applied(to: text)
        let ns = NSMutableString(string: edited)
        if selection.length == 0 {
            ns.insert("|", at: selection.location)
        } else {
            ns.insert("»", at: selection.location + selection.length)
            ns.insert("«", at: selection.location)
        }
        return ns as String
    }

    func testOutsideATagTheKindsAreOffered() {
        XCTAssertEqual(choices("Hello |world").1.map(\.title), MarkupSyntax.kinds)
        XCTAssertEqual(pick("mood", in: "Hello |world"),
                       #"Hello <!-- tts:mood value="|" --><!-- /tts:mood -->world"#)
        XCTAssertTrue(choices("x|").1.allSatisfy(\.completesFurther))
    }

    func testASelectionIsWrapped() {
        XCTAssertEqual(pick("speaker", in: "Say «this» now"),
                       #"Say <!-- tts:speaker value="|" -->this<!-- /tts:speaker --> now"#)
    }

    func testPlainTextHasItsOwnTags() {
        XCTAssertEqual(pick("speed", in: "Go |on", .plain), #"Go [tts:speed value="|"][/tts:speed]on"#)
        XCTAssertEqual(pick("excited", in: #"[tts:mood value="ex|"][/tts:mood]"#, .plain),
                       #"[tts:mood value="excited"]|[/tts:mood]"#)
    }

    func testAnOpenerStartedIsCompleted() {
        XCTAssertEqual(pick("mood", in: "Hi <!-|"), #"Hi <!-- tts:mood value="|" --><!-- /tts:mood -->"#)
        XCTAssertEqual(pick("mood", in: "Hi <!--|"), #"Hi <!-- tts:mood value="|" -->"#)
    }

    func testAKindStartedIsCompleted() {
        XCTAssertEqual(choices("<!-- tts:spe|").1.map(\.title), ["speed", "speaker"])
        XCTAssertEqual(choices("<!-- tts:m|").1.map(\.title), ["mood"])
        XCTAssertEqual(pick("mood", in: "<!-- tts:m|"), #"<!-- tts:mood value="|" -->"#)
        XCTAssertEqual(pick("language", in: "<!-- tt|"), #"<!-- tts:language value="|" -->"#)
    }

    func testAKindInAFinishedTagIsReplacedAlone() {
        XCTAssertEqual(pick("speed", in: #"<!-- tts:sp|eaker value="1.2" -->"#),
                       #"<!-- tts:speed| value="1.2" -->"#)
    }

    func testAClosingTagIsFinished() {
        XCTAssertEqual(pick("mood", in: "Sad.<!-- /tts:m|"), "Sad.<!-- /tts:mood -->|")
        XCTAssertEqual(pick("mood", in: "Sad.<!-- /tts:mood|"), "Sad.<!-- /tts:mood -->|")
        XCTAssertEqual(pick("-->", in: "Sad.<!-- /tts:mood |"), "Sad.<!-- /tts:mood -->|")
    }

    func testTheValueIsAskedFor() {
        XCTAssertEqual(pick("value", in: "<!-- tts:mood |"), #"<!-- tts:mood value="|" -->"#)
        XCTAssertEqual(pick("value", in: "<!-- tts:mood val|"), #"<!-- tts:mood value="|" -->"#)
        XCTAssertEqual(pick("value", in: "<!-- tts:mood | -->"), #"<!-- tts:mood value="|" -->"#)
    }

    func testValuesMatchingWhatIsTyped() {
        XCTAssertEqual(choices(#"<!-- tts:speaker value="L|"#).1.map(\.title), ["Liam", "Lily"])
        XCTAssertEqual(choices(#"<!-- tts:speaker value="|"#).1.map(\.title), ["Liam", "Lily", "Fable"])
        XCTAssertEqual(pick("Liam", in: #"<!-- tts:speaker value="Li|"#), #"<!-- tts:speaker value="Liam" -->|"#)
        XCTAssertEqual(pick("German", in: #"<!-- tts:language value="|" -->Hallo"#),
                       #"<!-- tts:language value="German" -->|Hallo"#)
        XCTAssertEqual(choices(#"<!-- tts:speaker value="Q|"#).1, [])
    }

    func testAValueWrittenIsReplacedWhole() {
        XCTAssertEqual(pick("calm", in: #"<!-- tts:mood value="ex|cited" -->Hey"#), nil)
        XCTAssertEqual(pick("calm", in: #"<!-- tts:mood value="|excited" -->Hey"#),
                       #"<!-- tts:mood value="calm" -->|Hey"#)
    }

    func testASpeedIsSuggestedToBeTypedOver() {
        XCTAssertEqual(pick("120%", in: #"<!-- tts:speed value="|" -->"#), #"<!-- tts:speed value="«120»%" -->"#)
        XCTAssertEqual(pick("120%", in: #"<!-- tts:speed value="|"#), #"<!-- tts:speed value="«120»%" -->"#)
    }

    func testTheEndOfATagIsAdded() {
        XCTAssertEqual(pick("-->", in: #"<!-- tts:mood value="sad"|"#), #"<!-- tts:mood value="sad" -->|"#)
        XCTAssertEqual(choices(#"<!-- tts:mood value="sad"| -->"#).1, [])
    }

    func testAnotherCommentIsNotATag() {
        XCTAssertEqual(choices("<!-- a note |").1.map(\.title), MarkupSyntax.kinds)
    }
}

final class TextFormatTests: XCTestCase {
    func testPlainTextIsReadAsItIs() {
        let source = "# Not a heading\n- not *an* item\n\nSecond [tts:mood value=\"sad\"]sadly[/tts:mood]."
        let blocks = TextReader.blocks(in: source, format: .plain)
        XCTAssertEqual(blocks.map(\.text), ["Not a heading - not an item", "Second sadly."])
        XCTAssertEqual(blocks[1].runs.map(\.style.mood), [nil, "sad"], "the full stop ends the sad part")
    }

    func testEachFormatHasItsOwnTags() {
        let markdown = #"A <!-- tts:mood value="sad" -->b<!-- /tts:mood --> [tts:mood value="calm"]c"#
        XCTAssertEqual(TextReader.blocks(in: markdown, format: .markdown)[0].runs.map(\.style.mood), [nil, "sad", nil])
        XCTAssertEqual(TextReader.blocks(in: markdown, format: .plain)[0].runs.map(\.style.mood), [nil, "calm"])
    }

    func testTheFileTellsTheFormat() {
        XCTAssertEqual(TextFormat(fileExtension: "MD"), .markdown)
        XCTAssertEqual(TextFormat(fileExtension: "txt"), .plain)
        XCTAssertNil(TextFormat(fileExtension: "rtf"))
    }

    func testTheLanguageTagIsKept() {
        let source = #"Hello. <!-- tts:language value="German" -->Hallo.<!-- /tts:language --> Bye."#
        XCTAssertEqual(TextReader.blocks(in: source)[0].runs.map(\.style.language), [nil, "German", nil])
    }

    func testLanguagesAreFoundByIdOrName() {
        let kokoro = KokoroEngine.shared
        XCTAssertEqual(kokoro.language(named: "es")?.id, "es")
        XCTAssertEqual(kokoro.language(named: "spanish")?.id, "es")
        XCTAssertEqual(kokoro.language(named: "English")?.id.hasPrefix("en"), true)
        XCTAssertNil(kokoro.language(named: "Hungarian"))
    }
}

final class SetTagCompletionTests: XCTestCase {
    private let completer = MarkupCompleter(syntax: .markdown) { kind, tag in
        switch kind {
        case "language": ["English (US)", "Hungarian"]
        case "model": ["Kokoro", "Piper"]
        case "speaker": tag["model"] == "Piper" ? ["Anna", "Imre"] : ["Heart", "Fable"]
        default: []
        }
    }

    private func pick(_ title: String, in marked: String) -> String? {
        var text = marked
        let cursor = text.firstIndex(of: "|")!
        text.remove(at: cursor)
        guard let choice = completer.choices(in: text, selection: cursor..<cursor).first(where: { $0.title == title })
        else { return nil }
        let (edited, selection) = choice.edit.applied(to: text)
        let ns = NSMutableString(string: edited)
        if selection.length > 0 { ns.insert("»", at: NSMaxRange(selection)) }
        ns.insert(selection.length > 0 ? "«" : "|", at: selection.location)
        return ns as String
    }

    private func titles(_ marked: String) -> [String] {
        var text = marked
        let cursor = text.firstIndex(of: "|")!
        text.remove(at: cursor)
        return completer.choices(in: text, selection: cursor..<cursor).map(\.title)
    }

    func testSetIsOfferedAndStaysOpen() {
        XCTAssertTrue(titles("x |").contains("set"))
        XCTAssertEqual(pick("set", in: "Hi |there"), "Hi <!-- tts:set | -->there")
        XCTAssertEqual(pick("set", in: "<!-- tts:se|"), "<!-- tts:set | -->")
    }

    func testTheAttributesNotWrittenAreOffered() {
        XCTAssertEqual(titles("<!-- tts:set | -->"), MarkupSyntax.setAttributes)
        XCTAssertEqual(titles(#"<!-- tts:set language="hu" | -->"#), ["model", "speaker", "speed", "mood"])
        XCTAssertEqual(pick("model", in: #"<!-- tts:set language="hu"| -->"#),
                       #"<!-- tts:set language="hu" model="|" -->"#)
        XCTAssertEqual(pick("speaker", in: "<!-- tts:set sp|"), #"<!-- tts:set speaker="|" -->"#)
    }

    func testValuesFollowTheRestOfTheTag() {
        XCTAssertEqual(titles(#"<!-- tts:set model="Piper" speaker="| -->"#), ["Anna", "Imre"])
        XCTAssertEqual(titles(#"<!-- tts:set speaker="|" -->"#), ["Heart", "Fable"])
        XCTAssertEqual(pick("Imre", in: #"<!-- tts:set model="Piper" speaker="I|" -->Szia"#),
                       #"<!-- tts:set model="Piper" speaker="Imre" -->|Szia"#)
        XCTAssertEqual(pick("120%", in: #"<!-- tts:set speed="|"#), #"<!-- tts:set speed="«120»%" -->"#)
    }

    func testAnAttributeWrittenBeforeAnotherIsSpacedFromIt() {
        XCTAssertEqual(pick("language", in: #"<!-- tts:set lang|speaker="" -->"#),
                       #"<!-- tts:set language="|" speaker="" -->"#)
        XCTAssertEqual(pick("Hungarian", in: #"<!-- tts:set language="|" speaker="" -->"#),
                       #"<!-- tts:set language="Hungarian" speaker="" -->|"#)
        XCTAssertEqual(pick("=\"\"", in: #"<!-- tts:set language=|speaker="" -->"#),
                       #"<!-- tts:set language="|" speaker="" -->"#)
        // Written together, they are still read as two.
        XCTAssertEqual(titles(#"<!-- tts:set language="Hungarian"speaker="|" -->"#), ["Heart", "Fable"])
    }

    func testTheOpenTagsAreOfferedToBeClosed() {
        XCTAssertEqual(Array(titles("<!-- tts:speed value=\"90%\" -->Slow |").prefix(2)),
                       ["Close /tts:speed", "speed"])
        let nested = #"<!-- tts:speaker value="Liam" --><!-- tts:speed value="90%" -->a<!-- tts:mood value="calm" -->b |"#
        XCTAssertEqual(Array(titles(nested).prefix(3)),
                       ["Close /tts:mood", "Close /tts:mood /tts:speed", "Close /tts:mood /tts:speed /tts:speaker"])
        XCTAssertEqual(pick("Close /tts:mood /tts:speed", in: nested),
                       String(nested.dropLast()) + "<!-- /tts:mood --><!-- /tts:speed -->|")
        // What is closed already is not offered.
        XCTAssertEqual(titles(#"<!-- tts:mood value="calm" -->a<!-- /tts:mood --> |"#), MarkupSyntax.kinds)
    }
}

final class LenientTagTests: XCTestCase {
    func testAttributesNeedNoSpaceBetweenThem() {
        let tags = MarkupSyntax.markdown.tags(in: #"<!-- tts:set language="Hungarian"speaker="Imre" -->Szia"#)
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags.first?.attributes, ["language": "Hungarian", "speaker": "Imre"])
        XCTAssertEqual(MarkupSyntax.plain.tags(in: #"[tts:set speed="90%"mood='calm']"#).first?.attributes,
                       ["speed": "90%", "mood": "calm"])
        // The first one is still to be apart from the kind.
        XCTAssertTrue(MarkupSyntax.markdown.tags(in: #"<!-- tts:setlanguage="hu" -->"#).isEmpty)
    }
}

final class TextChangesTests: XCTestCase {
    private func changes(_ original: String, _ current: String) -> [(String, String)] {
        TextChanges.hunks(from: original, to: current).map {
            ((current as NSString).substring(with: $0.current), $0.originalText)
        }
    }

    func testChangesAreWholeWords() {
        XCTAssertEqual(changes("Fix teh typo.", "Fix the typo.").map(\.0), ["the"])
        XCTAssertEqual(changes("Fix teh typo.", "Fix the typo.").map(\.1), ["teh"])
    }

    func testNeighbouringChangesAreOne() {
        let found = changes("Fruit, e.g. apples.", "Fruit, for example apples.")
        XCTAssertEqual(found.map(\.0), ["for example"])
        XCTAssertEqual(found.map(\.1), ["e.g."])
    }

    func testAdditionsAndDeletions() {
        let hunks = TextChanges.hunks(from: "one two three", to: "one three four")
        XCTAssertEqual(hunks.filter(\.isDeletion).map(\.originalText), ["two "])
        XCTAssertEqual(hunks.filter(\.isAddition).count, 1)
        XCTAssertEqual(hunks.first(where: \.isDeletion)?.current.location, 4)
    }

    func testKeepingAChangeMakesItPartOfTheOriginal() {
        let original = "a teh b teh c", current = "a the b the c"
        let hunks = TextChanges.hunks(from: original, to: current)
        XCTAssertEqual(hunks.count, 2)
        let kept = TextChanges.keeping(hunks[0], of: original, current: current)
        XCTAssertEqual(kept, "a the b teh c")
        XCTAssertEqual(TextChanges.hunks(from: kept, to: current).count, 1)
    }

    func testTheSameTextHasNoChanges() {
        XCTAssertEqual(TextChanges.hunks(from: "Same.", to: "Same."), [])
    }
}

@MainActor
final class TextPreparerTests: XCTestCase {
    func testPartsAreParagraphsWithoutCodeOrTags() {
        let text = "# Title\n\nFirst, e.g. this.\nSame paragraph.\n\n```\ncode 2*4\n```\n\n<!-- tts:mood value=\"sad\" -->\n\nLast."
        let ns = text as NSString
        XCTAssertEqual(TextPreparer.parts(of: text, format: .markdown).map { ns.substring(with: $0.range) },
                       ["# Title", "First, e.g. this.\nSame paragraph.", "Last."])
    }

    /// Runs where Apple Intelligence is on; prints what it made, to look at.
    func testAppleIntelligenceWritesThingsOut() async throws {
        guard TextPreparer.unavailableReason == nil else { throw XCTSkip(TextPreparer.unavailableReason!) }
        let text = #"Fruit, e.g. apples, pears etc. are good. <!-- tts:speed value="0.8" -->Thats 2*4 = 8 aples."#
        let answer = try await TextPreparer.prepare(text, format: .markdown)
        let prepared = try XCTUnwrap(answer)
        print("Apple Intelligence: \(prepared)")
        XCTAssertTrue(prepared.contains(#"<!-- tts:speed value="0.8" -->"#))
        XCTAssertFalse(prepared.contains("e.g."))
        XCTAssertFalse(prepared.contains("*"))
    }
}

final class TextChangesMergingTests: XCTestCase {
    func testChangesWithASpaceBetweenAreOne() {
        let current = "Thats why two times four equals eight apples a week."
        let hunks = TextChanges.hunks(from: "Thats why 2*4 = 8 aples a week.", to: current)
        XCTAssertEqual(hunks.map { (current as NSString).substring(with: $0.current) },
                       ["two times four equals eight apples"])
        XCTAssertEqual(hunks.map(\.originalText), ["2*4 = 8 aples"])
    }
}
