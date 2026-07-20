import Foundation
import SwiftUI

/// Deep module that owns the narrow "favorite / played" snapshot list rows need.
///
/// Previously each list view duplicated `@State private var favoritePlayed =
/// FavoritePlayedState.from(APIClient.shared)` plus three `.onChange` blocks
/// observing `APIClient`'s `favoriteSlugs` / `favoriteShowIDs` / `listenedShowIDs`.
/// That re-implemented the same seam at every call site. This store is the single
/// adapter: it observes those three sets on `APIClient` and republishes one
/// `FavoritePlayedState` value, so rows (via `makeBroadcastRow`) and views read a
/// stable snapshot instead of the whole `APIClient`.
///
/// Mirrors `ActivePlaybackStore`: a `@MainActor` singleton attached to the
/// environment at the app root. `APIClient` calls `refresh()` whenever it mutates
/// one of the three underlying sets, so the store never polls or subscribes itself.
@MainActor
public final class FavoritePlayedStore: ObservableObject {
    public static let shared = FavoritePlayedStore()

    /// The single narrow snapshot list rows consume. Replaces the per-view
    /// `@State favoritePlayed` and the three `.onChange` blocks.
    @Published var state: FavoritePlayedState

    private init() {
        self.state = FavoritePlayedState.from(APIClient.shared)
    }

    /// Rebuilds the snapshot from the current `APIClient` state. Called by
    /// `APIClient` at the end of every mutation that touches the three underlying
    /// sets (login, logout, fetchFavorites, fetchListeningHistory, the toggle*
    /// methods, markAsPlayed). Guarded by `Equatable` on `FavoritePlayedState`
    /// so an unchanged value does not publish a needless view update.
    public func refresh() {
        let next = FavoritePlayedState.from(APIClient.shared)
        guard next != state else { return }
        state = next
    }
}
