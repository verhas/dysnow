import XCTest
@testable import Dysnow

final class TextChunkerTests: XCTestCase {
    func testJoinsShortSentences() {
        let chunks = TextChunker.chunks("Hi. Yes. This is a longer sentence that stands on its own. Bye.")
        XCTAssertEqual(chunks, ["Hi. Yes. This is a longer sentence that stands on its own.", "Bye."])
    }

    func testCutsLongSentencesBetweenWords() {
        let sentence = Array(repeating: "word", count: 50).joined(separator: " ")
        let chunks = TextChunker.chunks(sentence, maximumLength: 60)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 60 })
        XCTAssertEqual(chunks.joined(separator: " "), sentence)
    }

    func testCutsTextWithoutSpaces() {
        let chunks = TextChunker.chunks(String(repeating: "字", count: 25), minimumLength: 1, maximumLength: 10)
        XCTAssertEqual(chunks.map(\.count), [10, 10, 5])
    }

    func testEmptyTextHasNoChunks() {
        XCTAssertEqual(TextChunker.chunks("  \n\n "), [])
    }

    func testPackedPiecesHoldAsManySentencesAsFit() {
        let text = "Az idő jó volt. Ezért lesétáltunk a folyóhoz. Az egész délután ráment. De senki sem bánta. "
            + "Holnap reggel korán indulunk."
        let pieces = TextChunker.packed(text, maximumLength: 60)
        XCTAssertEqual(pieces, ["Az idő jó volt. Ezért lesétáltunk a folyóhoz.",
                                "Az egész délután ráment. De senki sem bánta.",
                                "Holnap reggel korán indulunk."])
        XCTAssertTrue(pieces.allSatisfy { $0.count <= 60 })
    }

    func testAQuickStartMakesTheFirstPieceShort() {
        let text = "Good morning to all of you who came here today. This is the second sentence. And this is the third one."
        let pieces = TextChunker.packed(text, maximumLength: 200, quickStart: true)
        XCTAssertEqual(pieces, ["Good morning to all of you who came here today.",
                                "This is the second sentence. And this is the third one."])
    }
}

final class ReadingTextTests: XCTestCase {
    func testTheTextToReadIsInTheLanguageRecordedIn() {
        XCTAssertTrue(ReadingText.neutral("hu").hasPrefix("Az idő jó volt"))
        XCTAssertTrue(ReadingText.neutral("en-gb").hasPrefix("The weather was fine"))
        XCTAssertTrue(ReadingText.neutral("pt-br").hasPrefix("O tempo"))
        XCTAssertTrue(ReadingText.forMood("excited", languageID: "hu").hasPrefix("Sikerült!"))
        // No mood sentence written in Polish: the everyday one, said in the mood.
        XCTAssertEqual(ReadingText.forMood("excited", languageID: "pl"), ReadingText.neutral("pl"))
    }
}
