import Foundation
import Combine

/// Narrow, high-frequency playback progress state (current time + duration).
///
/// Deliberately kept **separate** from `AudioPlayerManager` so the 1 Hz `currentTime` tick does
/// NOT invalidate views that observe `AudioPlayerManager` (notably `ContentView`, which hosts the
/// scrolling list and the overlaid player bar). With the old design, `currentTime` was a `@Published`
/// property on `AudioPlayerManager`; because `ObservableObject` subscriptions fire on *any* published
/// change, every 1 Hz tick re-rendered `ContentView` and its entire subtree — including the scroll
/// view — causing a visible stutter while scrolling during playback.
///
/// Only the player-bar views (`PlaybackSeekBar`, `PlayerBarView`, the expanded Now Playing sheet)
/// observe this store, so the per-second progress update is isolated to the small UI that actually
/// needs it.
@MainActor
public final class PlaybackProgressStore: ObservableObject {
    public static let shared = PlaybackProgressStore()

    @Published public private(set) var currentTime: Double = 0
    @Published public private(set) var duration: Double = 0

    /// Pushes the latest progress from `AudioPlayerManager`. Called on the 1 Hz time observer tick
    /// and whenever `AudioPlayerManager` mutates its internal `currentTime`/`duration`.
    func update(currentTime: Double, duration: Double) {
        self.currentTime = currentTime
        self.duration = duration
    }

    /// Resets progress to zero (e.g. on stop / new item / live switch).
    func reset() {
        self.currentTime = 0
        self.duration = 0
    }
}
