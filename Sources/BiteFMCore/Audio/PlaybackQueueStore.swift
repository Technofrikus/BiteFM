import Foundation
import SwiftUI

/// „Als Nächstes“-Warteschlange: nur die *kommenden* Ausgaben, nicht die laufende.
///
/// Bewusst simpel gehalten — keine Historie, kein Index auf eine aktuelle Position, jede Ausgabe
/// höchstens einmal (Identität über `terminID`). Die laufende Ausgabe bleibt allein Sache von
/// `AudioPlayerManager.currentItem`; beim natürlichen Ende holt der Player per `popNext()` den
/// nächsten Eintrag.
///
/// Persistiert als JSON in `UserDefaults` unter einem eigenen Schlüssel — getrennt vom
/// `AppRestorationStore`, dessen Snapshots nach 30 Tagen verfallen. Die Warteschlange soll das nicht.
@MainActor
public final class PlaybackQueueStore: ObservableObject {
    public static let shared = PlaybackQueueStore()

    @Published public private(set) var items: [ArchiveItem] {
        didSet {
            let ids = Set(items.map(\.terminID))
            if ids != queuedTerminIDs { queuedTerminIDs = ids }
            persist()
        }
    }
    /// Schmaler Snapshot für Listenzeilen: ändert sich nur, wenn sich die *Menge* ändert
    /// (nicht beim Umsortieren).
    @Published public private(set) var queuedTerminIDs: Set<Int>

    private let defaults: UserDefaults
    private let storageKey: String

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "BiteFM.playbackQueue.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        let loaded = Self.load(from: defaults, key: storageKey)
        self.items = loaded
        self.queuedTerminIDs = Set(loaded.map(\.terminID))
    }

    public var isEmpty: Bool { items.isEmpty }
    public var nextItem: ArchiveItem? { items.first }

    public func contains(_ item: ArchiveItem) -> Bool {
        queuedTerminIDs.contains(item.terminID)
    }

    /// Hängt hinten an. Bereits enthaltene Ausgaben bleiben an ihrer Position.
    public func enqueue(_ item: ArchiveItem) {
        guard !contains(item) else { return }
        items.append(item)
    }

    /// Fügt vorne ein; eine bereits enthaltene Ausgabe wird nach vorne verschoben.
    public func playNext(_ item: ArchiveItem) {
        var next = items
        next.removeAll { $0.terminID == item.terminID }
        next.insert(item, at: 0)
        guard next != items else { return }
        items = next
    }

    public func remove(_ item: ArchiveItem) {
        remove(terminID: item.terminID)
    }

    public func remove(terminID: Int) {
        guard queuedTerminIDs.contains(terminID) else { return }
        items.removeAll { $0.terminID == terminID }
    }

    public func remove(atOffsets offsets: IndexSet) {
        var next = items
        next.remove(atOffsets: offsets)
        items = next
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var next = items
        next.move(fromOffsets: source, toOffset: destination)
        guard next != items else { return }
        items = next
    }

    public func clear() {
        guard !items.isEmpty else { return }
        items = []
    }

    /// Entnimmt den ersten Eintrag (für das automatische Weiterspielen).
    public func popNext() -> ArchiveItem? {
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    // MARK: - Persistenz

    private func persist() {
        if items.isEmpty {
            defaults.removeObject(forKey: storageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [ArchiveItem] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ArchiveItem].self, from: data) else {
            return []
        }
        // Defensiv deduplizieren, falls ein alter/fremder Stand Duplikate enthält.
        var seen = Set<Int>()
        return decoded.filter { seen.insert($0.terminID).inserted }
    }
}
