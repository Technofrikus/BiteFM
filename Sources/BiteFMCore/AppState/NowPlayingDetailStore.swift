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

    /// Toolbar-Toggle ohne konkretes Item (öffnet den Platzhalter). Genutzt von den
    /// Listen-Toolbars, die kein `ArchiveItem` zur Hand haben.
    public func toggle() {
        if isPresented { dismiss() } else { isPresented = true }
    }

    /// Bindings, über die Listenansichten und `BroadcastRow` denselben Store treiben wie die
    /// Player-Leiste — ein einziger Inspector-Pfad, kein pro-View-`@State`-Duplikat mehr.
    public var isPresentedBinding: Binding<Bool> {
        Binding(
            get: { self.isPresented },
            set: { newValue in
                if newValue { self.isPresented = true } else { self.dismiss() }
            }
        )
    }

    public var itemBinding: Binding<ArchiveItem?> {
        Binding(
            get: { self.item },
            set: { newValue in
                if let newValue { self.present(newValue) } else { self.dismiss() }
            }
        )
    }
}
