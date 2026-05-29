import XCTest
@testable import BiteFMCore

final class ArchivAudioURLTests: XCTestCase {
    func testMakeRelativePathEncodesSpaces() {
        let url = ArchivAudioURL.make(from: "foo bar/baz.mp3")
        XCTAssertEqual(url?.absoluteString, "https://archiv.bytefm.com/foo%20bar/baz.mp3")
    }

    func testMakeAbsoluteURLPassthrough() {
        let url = ArchivAudioURL.make(from: "https://archiv.bytefm.com/episode.mp3")
        XCTAssertEqual(url?.absoluteString, "https://archiv.bytefm.com/episode.mp3")
    }

    func testMakeEmptyReturnsNil() {
        XCTAssertNil(ArchivAudioURL.make(from: "   "))
    }
}
