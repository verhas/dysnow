import XCTest
@testable import Dysnow

final class NumberSpellerTests: XCTestCase {
    private func english(_ text: String) -> String {
        NumberSpeller.spell(text, languageID: "en-gb")
    }

    func testYearsAreReadAsYears() {
        XCTAssertEqual(english("In 1848, a man"), "In eighteen forty-eight, a man")
        XCTAssertEqual(english("1905 and 1900"), "nineteen oh five and nineteen hundred")
        XCTAssertEqual(english("in 2005 and 2026"), "in two thousand five and twenty twenty-six")
    }

    func testOtherNumbers() {
        XCTAssertEqual(english("Chapter 2: 25 years"), "Chapter two: twenty-five years")
        XCTAssertEqual(english("12,500 people"), "twelve thousand five hundred people")
        XCTAssertEqual(english("3.5 metres"), "three point five metres")
        XCTAssertEqual(english("9999 items"), "nine thousand nine hundred ninety-nine items")
    }

    func testDigitsInsideWordsAreLeftAlone() {
        XCTAssertEqual(english("an MP3 in 4K"), "an MP3 in 4K")
        XCTAssertEqual(english("version 1.2.3"), "version 1.2.3")
    }

    func testOtherLanguages() {
        XCTAssertEqual(NumberSpeller.spell("3,5 Meter", languageID: "de"), "drei Komma fünf Meter")
        XCTAssertEqual(NumberSpeller.spell("1848", languageID: "de"), "eintausendachthundertachtundvierzig")
    }
}
