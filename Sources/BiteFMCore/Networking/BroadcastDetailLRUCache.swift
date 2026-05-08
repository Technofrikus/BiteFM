import Foundation

/// Bounded LRU cache for decoded `BroadcastDetail` payloads to avoid unbounded heap growth
/// when browsing many episodes in a long-lived session.
struct BroadcastDetailLRUCache {
    private let capacity: Int
    private var storage: [Int: BroadcastDetail] = [:]
    /// Most-recently-used at the end; least-recently-used at the front.
    private var order: [Int] = []

    init(capacity: Int = 50) {
        self.capacity = max(1, capacity)
    }

    mutating func clear() {
        storage.removeAll(keepingCapacity: false)
        order.removeAll(keepingCapacity: false)
    }

    mutating func value(for id: Int) -> BroadcastDetail? {
        guard storage[id] != nil else { return nil }
        moveToMRU(id)
        return storage[id]
    }

    mutating func set(_ id: Int, detail: BroadcastDetail) {
        if storage[id] != nil {
            removeFromOrder(id)
        }
        storage[id] = detail
        order.append(id)
        evictIfNeeded()
    }

    var count: Int { storage.count }

    private mutating func moveToMRU(_ id: Int) {
        removeFromOrder(id)
        order.append(id)
    }

    private mutating func removeFromOrder(_ id: Int) {
        if let idx = order.firstIndex(of: id) {
            order.remove(at: idx)
        }
    }

    private mutating func evictIfNeeded() {
        while order.count > capacity {
            let victim = order.removeFirst()
            storage.removeValue(forKey: victim)
        }
    }
}
