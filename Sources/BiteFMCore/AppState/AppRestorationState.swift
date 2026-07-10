import Foundation

/// Persistierter UI-/Wiedergabe-Schnappschuss zur Wiederherstellung des App-Zustands beim Cold Launch.
///
/// Bewusst klein gehalten: nur stabile IDs, semantische Routen und ein einzelner `ArchiveItem`-Snapshot
/// für die zuletzt aktive Ausgabe. Listeninhalte oder View-Hierarchien werden nicht serialisiert; alles
/// landet als JSON in `UserDefaults`, weshalb keine SwiftData-Migration nötig ist.
public struct AppRestorationState: Codable, Equatable {
    /// Aktueller Versionsstempel — wird bei strukturellen Änderungen angehoben, alte Snapshots werden dann verworfen.
    public static let currentVersion: Int = 1

    public var version: Int
    public var savedAt: Date
    public var selectedRoot: SelectedRoot?
    public var lastPlaybackSession: PlaybackSession?
    public var navigationRoutes: NavigationRoutes

    public init(
        version: Int = AppRestorationState.currentVersion,
        savedAt: Date = Date(),
        selectedRoot: SelectedRoot? = nil,
        lastPlaybackSession: PlaybackSession? = nil,
        navigationRoutes: NavigationRoutes = NavigationRoutes()
    ) {
        self.version = version
        self.savedAt = savedAt
        self.selectedRoot = selectedRoot
        self.lastPlaybackSession = lastPlaybackSession
        self.navigationRoutes = navigationRoutes
    }
}

// MARK: - Root selection

extension AppRestorationState {
    /// Wurzelauswahl: aktiver Tab (iPhone) bzw. Sidebar-Eintrag (iPad/Mac).
    /// Beide Plattformen teilen sich die Codierung — beim Restore wird auf das Layout der laufenden Plattform abgebildet.
    public enum SelectedRoot: Codable, Equatable {
        case live
        case archiveNew
        case archive
        case downloads
        case favoriteEpisodes
        case favoriteTracks
        case favoritesHub
        /// Sidebar-Eintrag „Sendung als Favorit“. `slug` ist der App-interne Slug (vom `Show`-Modell abgeleitet),
        /// `title` als Fallback bei fehlendem Slug.
        case show(slug: String, title: String)

        public var stableKey: String {
            switch self {
            case .live: return "live"
            case .archiveNew: return "archiveNew"
            case .archive: return "archive"
            case .downloads: return "downloads"
            case .favoriteEpisodes: return "favoriteEpisodes"
            case .favoriteTracks: return "favoriteTracks"
            case .favoritesHub: return "favoritesHub"
            case .show(let slug, _): return "show:\(slug)"
            }
        }
    }
}

// MARK: - Last playback session

extension AppRestorationState {
    /// Schnappschuss der zuletzt aktiven Ausgabe. Live-Wiedergabe wird absichtlich nicht restauriert, weil sich der Stream
    /// laufend ändert und automatisches Anspielen beim Cold Launch unerwünscht wäre.
    public struct PlaybackSession: Codable, Equatable {
        public var terminID: Int
        public var position: Double
        public var duration: Double
        public var wasPlaying: Bool
        public var savedAt: Date
        /// Vollständige Kopie des `ArchiveItem`. Reicht aus, um Mini-/Now-Playing-UI ohne Netzwerk wiederherzustellen.
        public var item: ArchiveItem

        public init(
            terminID: Int,
            position: Double,
            duration: Double,
            wasPlaying: Bool,
            savedAt: Date,
            item: ArchiveItem
        ) {
            self.terminID = terminID
            self.position = position
            self.duration = duration
            self.wasPlaying = wasPlaying
            self.savedAt = savedAt
            self.item = item
        }
    }
}

// MARK: - Navigation routes (optional deep links inside tabs)

extension AppRestorationState {
    /// Eine semantische Route innerhalb eines Tabs. Nur Werte, keine Views — beim Restore wird die passende View neu gebaut.
    public enum DeepRoute: Codable, Equatable, Hashable {
        case show(slug: String, title: String, id: Int?)
        case favoriteEpisodes
        case favoriteTracks
    }

    public struct NavigationRoutes: Codable, Equatable {
        public var archive: [DeepRoute]
        public var favorites: [DeepRoute]
        public var archiveNew: [DeepRoute]

        public init(
            archive: [DeepRoute] = [],
            favorites: [DeepRoute] = [],
            archiveNew: [DeepRoute] = []
        ) {
            self.archive = archive
            self.favorites = favorites
            self.archiveNew = archiveNew
        }
    }
}

// MARK: - Scroll anchors removed
// Die Scroll-Anker-Wiederherstellung beim Re-Öffnen wurde entfernt (verwirrendes Springen).
// Die `ScrollAnchors`-Struktur ist daher entfernt.
