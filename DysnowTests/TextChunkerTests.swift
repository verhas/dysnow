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
}
