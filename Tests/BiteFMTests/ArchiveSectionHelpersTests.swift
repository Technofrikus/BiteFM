import XCTest
@testable import BiteFMCore

final class ArchiveSectionHelpersTests: XCTestCase {

    func testIndexLetterDigitsGroupToHash() {
        XCTAssertEqual(ArchiveSectionHelpers.indexLetter(forShowTitle: "3 Nach 9"), "#")
        XCTAssertEqual(ArchiveSectionHelpers.indexLetter(forShowTitle: "  2024 "), "#")
    }

    func testIndexLetterLeadingLetterUppercasedDE() {
        XCTAssertEqual(ArchiveSectionHelpers.indexLetter(forShowTitle: "aktuelle welle"), "A")
        XCTAssertEqual(ArchiveSectionHelpers.indexLetter(forShowTitle: "Übergrün"), "Ü")
    }

    func testIndexLetterPunctuationFallsBackToHash() {
        XCTAssertEqual(ArchiveSectionHelpers.indexLetter(forShowTitle: "! Sonderfall"), "#")
    }
}
