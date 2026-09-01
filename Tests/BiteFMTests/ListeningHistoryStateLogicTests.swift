import XCTest
@testable import BiteFMCore

final class ListeningHistoryStateLogicTests: XCTestCase {
    func testVisibleHistoryIncludesServerAndPendingEntries() {
        let visible = ListeningHistoryStateLogic.visibleShowIDs(
            serverIDs: [1, 2],
            pendingIDs: [2, 3]
        )

        XCTAssertEqual(visible, [1, 2, 3])
    }

    func testPendingEntryIsPreservedWhenMissingFromServer() {
        XCTAssertFalse(
            ListeningHistoryStateLogic.shouldDeleteLocalEntry(
                showID: 3,
                pendingSync: true,
                serverIDs: [1, 2]
            )
        )
    }

    func testConfirmedEntryMissingFromServerCanBeDeleted() {
        XCTAssertTrue(
            ListeningHistoryStateLogic.shouldDeleteLocalEntry(
                showID: 3,
                pendingSync: false,
                serverIDs: [1, 2]
            )
        )
    }

    func testServerEntryIsNeverDeleted() {
        XCTAssertFalse(
            ListeningHistoryStateLogic.shouldDeleteLocalEntry(
                showID: 2,
                pendingSync: false,
                serverIDs: [1, 2]
            )
        )
    }
}
