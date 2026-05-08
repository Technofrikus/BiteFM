import Foundation
import Combine

/// Persistiert kleine UI- und Wiedergabe-Snapshots in `UserDefaults` und stellt sie beim Cold Launch wieder zur Verfügung.
///
/// Bewusst leichtgewichtig: Schreibvorgänge werden gedrosselt, Snapshots älter als `maxSnapshotAge`
/// werden ignoriert und nicht in die Restoration-Pipeline gespeist.
@MainActor
public final class AppRestorationStore: ObservableObject {
    public static let shared = AppRestorationStore()

    @Published public private(set) var state: AppRestorationState

    /// Zeitspanne, ab der ein gespeicherter Snapshot als veraltet gilt. Vermeidet das Wiederbeleben monatealter Zustände
    /// (z. B. Sendungen, die im API nicht mehr existieren oder für den Nutzer keinen Bezug mehr haben).
    public let maxSnapshotAge: TimeInterval = 60 * 60 * 24 * 30

    private let defaults: UserDefaults
    private let storageKey: String
    private let writeDebounce: TimeInterval

    /// Drosselung: Wir beschreiben `UserDefaults` nicht synchron pro Tastendruck/Scroll-Pixel, sondern bündeln Änderungen.
    private var flushWorkItem: DispatchWorkItem?

    /// Letzter persistierter JSON-Hash, um redundante Writes (gleicher Inhalt) zu vermeiden.
    private var lastWrittenSignature: Int?

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "BiteFM.appRestorationState.v1",
        writeDebounce: TimeInterval = 0.5
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.writeDebounce = writeDebounce
        self.state = Self.loadState(from: defaults, key: storageKey)
        self.lastWrittenSignature = Self.signature(of: self.state)
    }

    // MARK: - Public read helpers

    /// Liefert den letzten Wiedergabe-Snapshot, falls er noch nicht zu alt ist und ein gültiges `ArchiveItem` enthält.
    public var validLastPlaybackSession: AppRestorationState.PlaybackSession? {
        guard let session = state.lastPlaybackSession else { return nil }
        guard !isStale(savedAt: session.savedAt) else { return nil }
        guard !session.item.audioFile1.isEmpty || !session.item.audioFile2.isEmpty || !session.item.audioFile3.isEmpty else { return nil }
        return session
    }

    /// Liefert den persistierten Wurzeleintrag, sofern der Snapshot insgesamt noch nicht veraltet ist.
    public var validSelectedRoot: AppRestorationState.SelectedRoot? {
        guard !isStale(savedAt: state.savedAt) else { return nil }
        return state.selectedRoot
    }

    public var validNavigationRoutes: AppRestorationState.NavigationRoutes {
        guard !isStale(savedAt: state.savedAt) else { return AppRestorationState.NavigationRoutes() }
        return state.navigationRoutes
    }

    public var validScrollAnchors: AppRestorationState.ScrollAnchors {
        guard !isStale(savedAt: state.savedAt) else { return AppRestorationState.ScrollAnchors() }
        return state.scrollAnchors
    }

    // MARK: - Public mutation API

    public func setSelectedRoot(_ root: AppRestorationState.SelectedRoot?) {
        guard state.selectedRoot != root else { return }
        state.selectedRoot = root
        state.savedAt = Date()
        scheduleFlush()
    }

    public func setLastPlaybackSession(_ session: AppRestorationState.PlaybackSession?) {
        guard state.lastPlaybackSession != session else { return }
        state.lastPlaybackSession = session
        state.savedAt = Date()
        scheduleFlush()
    }

    /// Aktualisiert nur Position/Status der bereits gespeicherten Sitzung — sehr häufige Schreiboperation, daher gedrosselt.
    public func updatePlaybackPosition(_ position: Double, duration: Double, wasPlaying: Bool) {
        guard var session = state.lastPlaybackSession else { return }
        // Größere Toleranz: nur deutliche Änderungen markieren, sonst werden Position-Updates aus AVPlayer ständig persistiert.
        let positionChanged = abs(session.position - position) > 1.0
        let durationChanged = duration > 0 && abs(session.duration - duration) > 1.0
        let stateChanged = session.wasPlaying != wasPlaying
        guard positionChanged || durationChanged || stateChanged else { return }
        session.position = max(0, position)
        if duration > 0 { session.duration = duration }
        session.wasPlaying = wasPlaying
        session.savedAt = Date()
        state.lastPlaybackSession = session
        state.savedAt = Date()
        scheduleFlush()
    }

    public func setNavigationRoutes(_ routes: AppRestorationState.NavigationRoutes) {
        guard state.navigationRoutes != routes else { return }
        state.navigationRoutes = routes
        state.savedAt = Date()
        scheduleFlush()
    }

    public func setArchivePath(_ path: [AppRestorationState.DeepRoute]) {
        guard state.navigationRoutes.archive != path else { return }
        state.navigationRoutes.archive = path
        state.savedAt = Date()
        scheduleFlush()
    }

    public func setArchiveNewPath(_ path: [AppRestorationState.DeepRoute]) {
        guard state.navigationRoutes.archiveNew != path else { return }
        state.navigationRoutes.archiveNew = path
        state.savedAt = Date()
        scheduleFlush()
    }

    public func setFavoritesPath(_ path: [AppRestorationState.DeepRoute]) {
        guard state.navigationRoutes.favorites != path else { return }
        state.navigationRoutes.favorites = path
        state.savedAt = Date()
        scheduleFlush()
    }

    public func setArchiveScrollAnchor(letter: String?) {
        guard state.scrollAnchors.archiveLetter != letter else { return }
        state.scrollAnchors.archiveLetter = letter
        state.savedAt = Date()
        scheduleFlush()
    }

    public func setArchiveNewScrollAnchor(terminID: Int?) {
        guard state.scrollAnchors.archiveNewTerminID != terminID else { return }
        state.scrollAnchors.archiveNewTerminID = terminID
        state.savedAt = Date()
        scheduleFlush()
    }

    public func setFavoriteEpisodesScrollAnchor(terminID: Int?) {
        guard state.scrollAnchors.favoriteEpisodesTerminID != terminID else { return }
        state.scrollAnchors.favoriteEpisodesTerminID = terminID
        state.savedAt = Date()
        scheduleFlush()
    }

    /// Erzwingt sofortiges Schreiben, z. B. bei Background/Termination.
    public func flushNow() {
        flushWorkItem?.cancel()
        flushWorkItem = nil
        persistIfChanged()
    }

    /// Verwirft den gespeicherten Wiedergabe-Snapshot (z. B. wenn die Ausgabe das Ende erreicht hat).
    public func clearLastPlaybackSession() {
        setLastPlaybackSession(nil)
    }

    // MARK: - Persistence

    private func scheduleFlush() {
        flushWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            // Auf MainActor zurückspringen — `state` ist Main-isoliert.
            Task { @MainActor [weak self] in
                self?.persistIfChanged()
            }
        }
        flushWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + writeDebounce, execute: work)
    }

    private func persistIfChanged() {
        let signature = Self.signature(of: state)
        guard signature != lastWrittenSignature else { return }
        do {
            let data = try Self.encoder.encode(state)
            defaults.set(data, forKey: storageKey)
            lastWrittenSignature = signature
        } catch {
            LogManager.shared.log("AppRestorationStore: encode failed: \(error.localizedDescription)", type: .error)
        }
    }

    private func isStale(savedAt: Date) -> Bool {
        Date().timeIntervalSince(savedAt) > maxSnapshotAge
    }

    // MARK: - Static helpers

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static func loadState(from defaults: UserDefaults, key: String) -> AppRestorationState {
        guard let data = defaults.data(forKey: key) else {
            return AppRestorationState()
        }
        do {
            let decoded = try decoder.decode(AppRestorationState.self, from: data)
            // Bei Versionsbruch: Reset, damit alte Schemas nicht zu Folgefehlern führen.
            guard decoded.version == AppRestorationState.currentVersion else {
                return AppRestorationState()
            }
            return decoded
        } catch {
            // Korrupten Snapshot ignorieren — UI startet mit Defaults.
            LogManager.shared.log("AppRestorationStore: decode failed, resetting: \(error.localizedDescription)", type: .error)
            defaults.removeObject(forKey: key)
            return AppRestorationState()
        }
    }

    private static func signature(of state: AppRestorationState) -> Int {
        guard let data = try? encoder.encode(state) else { return 0 }
        return data.hashValue
    }
}
