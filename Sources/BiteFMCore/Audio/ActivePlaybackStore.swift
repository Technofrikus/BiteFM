import Foundation
import SwiftUI

/// Lightweight, narrow view-model that exposes only the "which row is active" state of
/// `AudioPlayerManager`. List rows subscribe to this instead of the full `AudioPlayerManager`,
/// so the 1 Hz `currentTime` tick (and other high-frequency publishers) no longer re-render
/// every visible row while scrolling.
///
/// `activeTerminID` is `nil` when nothing archive-related is active (e.g. live-only playback),
/// which keeps rows from highlighting during live playback.
@MainActor
public final class ActivePlaybackStore: ObservableObject {
    public static let shared = ActivePlaybackStore()

    @Published public private(set) var activeTerminID: Int?
    @Published public private(set) var isActivePlaying: Bool = false
    @Published public private(set) var isActivePreparing: Bool = false
    /// Show identity of the active archive item, so list rows (keyed by show) can highlight
    /// without observing the full `AudioPlayerManager`. Mirrors `ArchiveItem.sendungID`/`sendungSlug`.
    @Published public private(set) var activeSendungID: Int?
    @Published public private(set) var activeSendungSlug: String?

    private weak var playerManager: AudioPlayerManager?

    private init() {}

    /// Wire to the player manager and start mirroring the relevant, low-frequency state.
    /// Call once during bootstrap (after `AudioPlayerManager.setup`).
    public func attach(_ playerManager: AudioPlayerManager) {
        self.playerManager = playerManager
        sync()
    }

    /// Re-sync from the player manager's current state (e.g. after session restore).
    public func sync() {
        guard let pm = playerManager else { return }
        let newActive: Int? = pm.currentItem?.terminID
        let newPlaying = pm.currentItem != nil && pm.isPlaying && !pm.isLive
        let newPreparing = pm.preparingArchiveItemID != nil
        let newSendungID = pm.currentItem?.sendungID
        let newSendungSlug = pm.currentItem?.sendungSlug
        if newActive != activeTerminID
            || newPlaying != isActivePlaying
            || newPreparing != isActivePreparing
            || newSendungID != activeSendungID
            || newSendungSlug != activeSendungSlug {
            activeTerminID = newActive
            isActivePlaying = newPlaying
            isActivePreparing = newPreparing
            activeSendungID = newSendungID
            activeSendungSlug = newSendungSlug
        }
    }

    /// Call from `AudioPlayerManager` whenever the active item, playing flag, or preparing flag changes.
    public func notifyActiveStateChanged() {
        sync()
    }
}
