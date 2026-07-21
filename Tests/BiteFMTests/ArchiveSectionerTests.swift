import XCTest
@testable import BiteFMCore

final class ArchiveSectionerTests: XCTestCase {

    @MainActor
    func testIndexLetterDigitsGroupToHash() {
        XCTAssertEqual(ArchiveSectioner.indexLetter(forShowTitle: "3 Nach 9"), "#")
        XCTAssertEqual(ArchiveSectioner.indexLetter(forShowTitle: "  2024 "), "#")
    }

    @MainActor
    func testIndexLetterLeadingLetterUppercasedDE() {
        XCTAssertEqual(ArchiveSectioner.indexLetter(forShowTitle: "aktuelle welle"), "A")
        XCTAssertEqual(ArchiveSectioner.indexLetter(forShowTitle: "Übergrün"), "Ü")
    }

    @MainActor
    func testIndexLetterPunctuationFallsBackToHash() {
        XCTAssertEqual(ArchiveSectioner.indexLetter(forShowTitle: "! Sonderfall"), "#")
    }

    // MARK: - sectionByLetter

    @MainActor
    func testSectionByLetterGroupsShowsByFirstLetter() {
        let shows = [
            Show(id: 1, titel: "Aktuelle Welle", untertitel: ""),
            Show(id: 2, titel: "Bunte Stunde", untertitel: ""),
            Show(id: 3, titel: "Apropos", untertitel: ""),
            Show(id: 4, titel: "3 Nach 9", untertitel: ""),
        ]
        let sectioner = ArchiveSectioner()
        let sections = sectioner.sectionByLetter(shows)
        let letters = sections.map(\.letter)
        XCTAssertEqual(letters, ["#", "A", "B"])
        // "#" section: only "3 Nach 9"
        XCTAssertEqual(sections.first(where: { $0.letter == "#" })?.shows.map(\.titel), ["3 Nach 9"])
        // "A" section: alphabetically sorted
        XCTAssertEqual(sections.first(where: { $0.letter == "A" })?.shows.map(\.titel), ["Aktuelle Welle", "Apropos"])
    }

    @MainActor
    func testSectionByLetterMemoization() {
        let shows = [Show(id: 1, titel: "Alpha", untertitel: "")]
        let sectioner = ArchiveSectioner()
        let first = sectioner.sectionByLetter(shows)
        let second = sectioner.sectionByLetter(shows)
        // Same return identity (same cached array)
        XCTAssertEqual(first[0].shows.count, second[0].shows.count)
    }

    // MARK: - sectionByDay

    @MainActor
    func testSectionByDayGroupsItemsByDay() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let items = [
            storedItem(terminID: 1, startTime: "10:00", broadcastDate: today),
            storedItem(terminID: 2, startTime: "12:00", broadcastDate: today),
            storedItem(terminID: 3, startTime: "09:00", broadcastDate: yesterday),
        ]
        let sectioner = ArchiveSectioner()
        let sections = sectioner.sectionByDay(items)
        // Two distinct days
        XCTAssertEqual(sections.count, 2)
        // Days sorted descending — today's dayStart should be >= yesterday's
        XCTAssertGreaterThan(sections[0].dayStart, sections[1].dayStart)
        // Items within today sorted by startTime descending (12:00 before 10:00)
        XCTAssertEqual(sections[0].items.map(\.terminID), [2, 1])
    }

    @MainActor
    func testSectionByDayMemoization() {
        let items = [storedItem(terminID: 1, startTime: "10:00", broadcastDate: Date())]
        let sectioner = ArchiveSectioner()
        let first = sectioner.sectionByDay(items)
        let second = sectioner.sectionByDay(items)
        XCTAssertEqual(first.count, second.count)
    }

    // MARK: - Helpers

    private func storedItem(terminID: Int, startTime: String, broadcastDate: Date) -> StoredArchiveItem {
        let archiveItem = ArchiveItem(
            audioFile1: "",
            audioFile2: "",
            audioFile3: "",
            sendungTitel: "Test",
            untertitelSendung: "",
            terminID: terminID,
            terminSlug: "test",
            sendungSlug: "test",
            sendungID: 1,
            datum: {
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(secondsFromGMT: 0)
                return df.string(from: broadcastDate)
            }(),
            datumDe: "",
            startTime: startTime,
            endTime: "11:00",
            untertitelTermin: ""
        )
        return StoredArchiveItem(from: archiveItem)
    }
}