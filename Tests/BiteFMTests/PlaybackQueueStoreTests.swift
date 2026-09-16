import XCTest
@testable import BiteFMCore

@MainActor
final class PlaybackQueueStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private let storageKey = "BiteFM.playbackQueue.v1.tests"

    override func setUp() {
        super.setUp()
        // Pro Test eine isolierte Suite.
        suiteName = "PlaybackQueueStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        XCTAssertNotNil(defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeItem(_ terminID: Int, sendungID: Int? = nil) -> ArchiveItem {
        ArchiveItem(
            audioFile1: "https://example.invalid/\(terminID).mp3",
            audioFile2: "",
            audioFile3: "",
            sendungTitel: "Sendung \(terminID)",
            untertitelSendung: "",
            terminID: terminID,
            terminSlug: "termin-\(terminID)",
            sendungSlug: "sendung",
            sendungID: sendungID,
            datum: "2026-09-16",
            datumDe: "16.09.2026",
            startTime: "10:00",
            endTime: "12:00",
            untertitelTermin: ""
        )
    }

    private func makeStore() -> PlaybackQueueStore {
        PlaybackQueueStore(defaults: defaults, storageKey: storageKey)
    }

    private func ids(_ store: PlaybackQueueStore) -> [Int] {
        store.items.map(\.terminID)
    }

    // MARK: - Enqueue / playNext

    func testStartsEmpty() {
        let store = makeStore()
        XCTAssertTrue(store.isEmpty)
        XCTAssertNil(store.nextItem)
        XCTAssertTrue(store.queuedTerminIDs.isEmpty)
    }

    func testEnqueueAppendsAndIgnoresDuplicates() {
        let store = makeStore()
        store.enqueue(makeItem(1))
        store.enqueue(makeItem(2, sendungID: 7))
        store.enqueue(makeItem(3))
        XCTAssertEqual(ids(store), [1, 2, 3])

        // Duplikat (gleiche terminID) bleibt an seiner Position.
        store.enqueue(makeItem(1))
        XCTAssertEqual(ids(store), [1, 2, 3])
        XCTAssertEqual(store.nextItem?.terminID, 1)
    }

    func testPlayNextInsertsAtFront() {
        let store = makeStore()
        store.enqueue(makeItem(1))
        store.enqueue(makeItem(2))
        store.playNext(makeItem(3))
        XCTAssertEqual(ids(store), [3, 1, 2])
    }

    func testPlayNextMovesExistingEntryToFront() {
        let store = makeStore()
        [1, 2, 3].forEach { store.enqueue(makeItem($0)) }
        store.playNext(makeItem(3))
        XCTAssertEqual(ids(store), [3, 1, 2])

        // Bereits vorne: keine Änderung.
        store.playNext(makeItem(3))
        XCTAssertEqual(ids(store), [3, 1, 2])
        XCTAssertEqual(store.items.count, 3)
    }

    // MARK: - Remove / move / clear

    func testRemoveItem() {
        let store = makeStore()
        [1, 2, 3].forEach { store.enqueue(makeItem($0)) }
        store.remove(makeItem(2))
        XCTAssertEqual(ids(store), [1, 3])
        XCTAssertFalse(store.contains(makeItem(2)))
    }

    func testRemoveByTerminID() {
        let store = makeStore()
        [1, 2, 3].forEach { store.enqueue(makeItem($0)) }
        store.remove(terminID: 1)
        XCTAssertEqual(ids(store), [2, 3])

        // Unbekannte ID ist ein No-op.
        store.remove(terminID: 99)
        XCTAssertEqual(ids(store), [2, 3])
    }

    func testRemoveAtOffsets() {
        let store = makeStore()
        [1, 2, 3, 4].forEach { store.enqueue(makeItem($0)) }
        store.remove(atOffsets: IndexSet([0, 2]))
        XCTAssertEqual(ids(store), [2, 4])
        XCTAssertEqual(store.queuedTerminIDs, [2, 4])
    }

    func testMoveFromOffsetsToOffset() {
        let store = makeStore()
        [1, 2, 3, 4].forEach { store.enqueue(makeItem($0)) }

        // Erstes Element ans Ende (SwiftUI-onMove-Semantik).
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        XCTAssertEqual(ids(store), [2, 3, 4, 1])

        // Letztes Element nach vorne.
        store.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(ids(store), [1, 2, 3, 4])

        // Mehrere Elemente.
        store.move(fromOffsets: IndexSet([0, 1]), toOffset: 3)
        XCTAssertEqual(ids(store), [3, 1, 2, 4])

        // Umsortieren ändert die Menge nicht.
        XCTAssertEqual(store.queuedTerminIDs, [1, 2, 3, 4])
    }

    func testClear() {
        let store = makeStore()
        [1, 2].forEach { store.enqueue(makeItem($0)) }
        store.clear()
        XCTAssertTrue(store.isEmpty)
        XCTAssertTrue(store.queuedTerminIDs.isEmpty)

        // Leeren einer leeren Warteschlange ist unproblematisch.
        store.clear()
        XCTAssertTrue(store.isEmpty)
    }

    // MARK: - popNext

    func testPopNextReturnsFirstAndNilWhenEmpty() {
        let store = makeStore()
        [1, 2].forEach { store.enqueue(makeItem($0)) }

        XCTAssertEqual(store.popNext()?.terminID, 1)
        XCTAssertEqual(ids(store), [2])
        XCTAssertEqual(store.popNext()?.terminID, 2)
        XCTAssertTrue(store.isEmpty)
        XCTAssertNil(store.popNext())
        XCTAssertTrue(store.queuedTerminIDs.isEmpty)
    }

    // MARK: - queuedTerminIDs / contains

    func testQueuedTerminIDsMirrorsItems() {
        let store = makeStore()
        store.enqueue(makeItem(1))
        store.enqueue(makeItem(2))
        XCTAssertEqual(store.queuedTerminIDs, [1, 2])
        store.playNext(makeItem(3))
        XCTAssertEqual(store.queuedTerminIDs, [1, 2, 3])
        store.remove(terminID: 2)
        XCTAssertEqual(store.queuedTerminIDs, [1, 3])
        _ = store.popNext()
        XCTAssertEqual(store.queuedTerminIDs, Set(ids(store)))
        XCTAssertEqual(store.queuedTerminIDs, [1])
    }

    func testContains() {
        let store = makeStore()
        store.enqueue(makeItem(1))
        XCTAssertTrue(store.contains(makeItem(1)))
        // Identität nur über terminID, andere Felder egal.
        XCTAssertTrue(store.contains(makeItem(1, sendungID: 42)))
        XCTAssertFalse(store.contains(makeItem(2)))
    }

    // MARK: - Persistenz

    func testPersistenceRoundTripKeepsOrder() {
        let store = makeStore()
        [1, 2, 3].forEach { store.enqueue(makeItem($0)) }
        store.playNext(makeItem(3))
        store.enqueue(makeItem(4, sendungID: 5))

        let reloaded = makeStore()
        XCTAssertEqual(ids(reloaded), [3, 1, 2, 4])
        XCTAssertEqual(reloaded.items, store.items)
        XCTAssertEqual(reloaded.queuedTerminIDs, [1, 2, 3, 4])
        XCTAssertEqual(reloaded.items.last?.sendungID, 5)
    }

    func testEmptyQueueRemovesKey() {
        let store = makeStore()
        store.enqueue(makeItem(1))
        XCTAssertNotNil(defaults.data(forKey: storageKey))

        store.clear()
        XCTAssertNil(defaults.object(forKey: storageKey))

        store.enqueue(makeItem(2))
        _ = store.popNext()
        XCTAssertNil(defaults.object(forKey: storageKey))
        XCTAssertTrue(makeStore().isEmpty)
    }

    func testLoadDeduplicatesEntries() throws {
        let raw = [makeItem(1), makeItem(2), makeItem(1), makeItem(3), makeItem(2)]
        defaults.set(try JSONEncoder().encode(raw), forKey: storageKey)

        let store = makeStore()
        XCTAssertEqual(ids(store), [1, 2, 3])
        XCTAssertEqual(store.queuedTerminIDs, [1, 2, 3])
    }

    func testCorruptDataLoadsAsEmpty() {
        defaults.set(Data("not json".utf8), forKey: storageKey)
        let store = makeStore()
        XCTAssertTrue(store.isEmpty)
        XCTAssertTrue(store.queuedTerminIDs.isEmpty)

        // Nach einer Änderung wird der kaputte Stand überschrieben.
        store.enqueue(makeItem(1))
        XCTAssertEqual(ids(makeStore()), [1])
    }
}
