import XCTest
@testable import BiteFMCore

final class BroadcastDetailLRUCacheTests: XCTestCase {
    func testEvictsLeastRecentlyUsedWhenOverCapacity() {
        var cache = BroadcastDetailLRUCache(capacity: 3)

        cache.set(1, detail: Self.stubDetail(id: 1))
        cache.set(2, detail: Self.stubDetail(id: 2))
        cache.set(3, detail: Self.stubDetail(id: 3))

        XCTAssertEqual(cache.count, 3)
        XCTAssertNotNil(cache.value(for: 1))

        cache.set(4, detail: Self.stubDetail(id: 4))

        XCTAssertEqual(cache.count, 3)
        XCTAssertNil(cache.value(for: 2), "Expected LRU eviction of key 2 (oldest after MRU touches).")
        XCTAssertNotNil(cache.value(for: 1))
        XCTAssertNotNil(cache.value(for: 3))
        XCTAssertNotNil(cache.value(for: 4))
    }

    func testGetPromotesMiddleKeyToMRU() {
        var cache = BroadcastDetailLRUCache(capacity: 3)
        cache.set(1, detail: Self.stubDetail(id: 1))
        cache.set(2, detail: Self.stubDetail(id: 2))
        cache.set(3, detail: Self.stubDetail(id: 3))

        _ = cache.value(for: 2)

        cache.set(4, detail: Self.stubDetail(id: 4))

        XCTAssertNil(cache.value(for: 1), "Key 1 should be evicted; key 2 was touched and promoted.")
        XCTAssertNotNil(cache.value(for: 2))
        XCTAssertNotNil(cache.value(for: 3))
        XCTAssertNotNil(cache.value(for: 4))
    }

    func testClearRemovesAll() {
        var cache = BroadcastDetailLRUCache(capacity: 5)
        cache.set(1, detail: Self.stubDetail(id: 1))
        cache.clear()
        XCTAssertEqual(cache.count, 0)
        XCTAssertNil(cache.value(for: 1))
    }

    private static func stubDetail(id: Int) -> BroadcastDetail {
        let json = """
        {"id":\(id),"broadcast_title":"","show_subtitle":"","show_time":"","show_date":"","moderator":"","show_description":"","recordings":[]}
        """
        let data = Data(json.utf8)
        return try! JSONDecoder().decode(BroadcastDetail.self, from: data)
    }
}
