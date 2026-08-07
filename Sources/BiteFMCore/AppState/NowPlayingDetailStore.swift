import Foundation
import SwiftUI

/// Shared "show the currently playing item's details" state, so the player bar's info button
/// can open the same inspector/sheet the list rows use — regardless of which list or tab is
/// currently visible.
///
/// Mirrors `ActivePlaybackStore`: a `@MainActor` singleton attached to the environment at the
/// app root. The player bar sets `item`/`isPresented`; the root-level `broadcastInspector`
/// (in `ContentView`) observes them to present the detail sidebar/sheet.
@MainActor
public final class NowPlayingDetailStore: ObservableObject {
    public static let shared = NowPlayingDetailStore()

    @Published public var isPresented: Bool = false
    @Published public var item: ArchiveItem?

    private init() {}

    public func present(_ item: ArchiveItem) {
        self.item = item
        isPresented = true
    }

    public func dismiss() {
        isPresented = false
        item = nil
    }
}
