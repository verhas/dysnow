import XCTest
@testable import Dysnow

final class MarkdownReaderTests: XCTestCase {
    private func texts(_ source: String) -> [String] {
        TextReader.blocks(in: source).map(\.text)
    }

    func testHeadingsAreReadWithoutHashes() {
        XCTAssertEqual(texts("# Title\n## Second level ##\nText."), ["Title", "Second level", "Text."])
    }

    func testEmptyLinesSeparateParagraphsAndLinesRunOn() {
        let blocks = TextReader.blocks(in: "First line\nsame paragraph.\n\n\nSecond paragraph.")
        XCTAssertEqual(blocks.map(\.text), ["First line same paragraph.", "Second paragraph."])
        XCTAssertEqual(blocks[0].pauseAfter, TextReader.paragraphPause)
    }

    func testInlineMarkupIsTakenOut() {
        XCTAssertEqual(texts("Some **bold**, _italic_, `code` and a [link](https://example.com)."),
                       ["Some bold, italic, code and a link."])
    }

    func testListItemsAreBlocksOfTheirOwn() {
        let blocks = TextReader.blocks(in: "Shopping:\n\n- milk\n- [x] bread\n  with butter\n1. eggs")
        XCTAssertEqual(blocks.map(\.text), ["Shopping:", "milk", "bread with butter", "eggs"])
        XCTAssertEqual(blocks[1].pauseAfter, TextReader.listItemPause)
    }

    func testCodeBlocksQuotesRulesAndTables() {
        let source = """
        > Quoted
        > text.

        ```swift
        let x = 1
        ```
        ---
        | Name | Age |
        |------|----:|
        | Ann  | 42  |
        """
        XCTAssertEqual(texts(source), ["Quoted text.", "Name, Age", "Ann, 42"])
    }

    func testSymbolsAreNotSpoken() {
        XCTAssertEqual(TextReader.speakable("C# costs $5 & 50% → done 🎉 #tag *star*"),
                       "C costs $5 50% done tag star")
        XCTAssertEqual(TextReader.speakable("Ez egy próba: árvíztűrő tükörfúrógép!"),
                       "Ez egy próba: árvíztűrő tükörfúrógép!")
    }

    func testOnlySymbolsSaysNothing() {
        XCTAssertEqual(texts("***\n\n#\n\n* * *\n\n=== "), [])
    }

    func testFromCursorStartsAtTheSentence() {
        let source = "# Title\n\nOne. Two three. Four.\n\nLast."
        let cursor = source.range(of: "three")!.lowerBound
        XCTAssertEqual(TextReader.blocks(in: source, from: cursor).map(\.text), ["Two three. Four.", "Last."])
    }

    func testFromCursorInEmptyLineStartsAtTheNextBlock() {
        let source = "One.\n\n\nTwo."
        let cursor = source.index(source.startIndex, offsetBy: 5)
        XCTAssertEqual(TextReader.blocks(in: source, from: cursor).map(\.text), ["Two."])
    }

    func testFromCursorAtTheStartReadsEverything() {
        let source = "# Title\n\n- item"
        XCTAssertEqual(TextReader.blocks(in: source, from: source.startIndex).map(\.text), ["Title", "item"])
    }
}
