#if os(iOS)
import Foundation
import Intents
import SwiftData

/// Verarbeitet das Antippen eines Siri-Vorschlags (Lock Screen, Kopfhörer-Verbinden), den
/// `AudioPlayerManager.donateNowPlayingIntent` angelegt hat. Wird über
/// `application(_:handlerFor:)` im App-Prozess aufgerufen (In-App Intent Handling) — die App
/// läuft dafür ggf. nur im Hintergrund, daher wird direkt abgespielt statt nur UI geöffnet.
public final class NowPlayingIntentHandler: NSObject, INPlayMediaIntentHandling {
    public override init() {
        super.init()
    }

    public func handle(intent: INPlayMediaIntent, completion: @escaping (INPlayMediaIntentResponse) -> Void) {
        let identifier = intent.mediaItems?.first?.identifier
        Task { @MainActor in
            let started = AudioPlayerManager.shared.playFromNowPlayingIntent(identifier: identifier)
            completion(INPlayMediaIntentResponse(code: started ? .success : .failure, userActivity: nil))
        }
    }
}

extension AudioPlayerManager {
    /// Startet die Ausgabe hinter einem Siri-Vorschlag. Ohne erkennbare Ausgabe wird die zuletzt
    /// gehörte fortgesetzt. Gibt `false` zurück, wenn nichts abgespielt werden konnte.
    func playFromNowPlayingIntent(identifier: String?) -> Bool {
        guard let terminID = identifier.flatMap(Self.terminID(fromNowPlayingIntentIdentifier:)) else {
            return resumeLastArchivePlayback()
        }
        guard let item = archiveItemForNowPlayingIntent(terminID: terminID) else {
            LogManager.shared.log("Siri-Vorschlag: Ausgabe \(terminID) nicht gefunden", type: .error)
            return false
        }
        if currentItem?.terminID == terminID {
            // Bereits geladen (auch als wiederhergestellter Schnappschuss) — an der aktuellen Stelle weiter.
            if !isPlaying { togglePlayPause() }
            return true
        }
        // Ohne `initialPosition` setzt `play(item:)` an der gespeicherten Position fort.
        play(item: item)
        return true
    }

    private func resumeLastArchivePlayback() -> Bool {
        if currentItem == nil {
            restoreLastSessionSnapshotIfNeeded()
        }
        guard currentItem != nil, !isLive else { return false }
        if !isPlaying { togglePlayPause() }
        return true
    }

    /// Sucht die Ausgabe in allen lokalen Quellen, aus denen Vorschläge stammen können — ohne Netzwerk,
    /// da die App dafür evtl. nur kurz im Hintergrund gestartet wurde.
    private func archiveItemForNowPlayingIntent(terminID: Int) -> ArchiveItem? {
        if let current = currentItem, current.terminID == terminID {
            return current
        }
        if let session = restorationStore?.state.lastPlaybackSession, session.terminID == terminID {
            return session.item
        }
        if let queued = PlaybackQueueStore.shared.items.first(where: { $0.terminID == terminID }) {
            return queued
        }
        guard let container = modelContainer else { return nil }
        let context = ModelContext(container)
        let archiveDescriptor = FetchDescriptor<StoredArchiveItem>(
            predicate: #Predicate<StoredArchiveItem> { $0.terminID == terminID }
        )
        if let stored = try? context.fetch(archiveDescriptor).first {
            return stored.toArchiveItem()
        }
        let downloadDescriptor = FetchDescriptor<StoredDownloadedEpisode>(
            predicate: #Predicate<StoredDownloadedEpisode> { $0.terminID == terminID }
        )
        return (try? context.fetch(downloadDescriptor).first)?.toArchiveItem()
    }
}
#endif
