import XCTest
@testable import BiteFMCore

@MainActor
final class AppRestorationStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private let storageKey = "BiteFM.appRestorationState.v1.tests"

    override func setUp() {
        super.setUp()
        // Pro Test eine isolierte Suite, damit Tests sich gegenseitig nicht beeinflussen und auch nichts zurücklassen.
        suiteName = "AppRestorationStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        XCTAssertNotNil(defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Root selection

    func testPersistsAndReloadsSelectedRoot() {
        let store = AppRestorationStore(defaults: defaults, storageKey: storageKey, writeDebounce: 0)
        store.setSelectedRoot(.archive)
        store.flushNow()

        let reloaded = AppRestorationStore(defaults: defaults, storageKey: storageKey, writeDebounce: 0)
        XCTAssertEqual(reloaded.validSelectedRoot, .archive)
    }

    func testIgnoresStaleSelectedRoot() {
        // Snapshot manuell mit weit in der Vergangenheit liegendem `savedAt` schreiben — Store muss ihn als veraltet
        // erkennen und für die Wiederherstellung verwerfen.
        let stale = AppRestorationState(
            version: AppRestorationState.currentVersion,
            savedAt: Date(timeIntervalSinceNow: -60 * 60 * 24 * 60), // 60 Tage alt
            selectedRoot: .favoriteEpisodes
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(stale)
        defaults.set(data, forKey: storageKey)

        let store = AppRestorationStore(defaults: defaults, storageKey: storageKey, writeDebounce: 0)
        XCTAssertNil(store.validSelectedRoot, "Stale snapshot should not be surfaced for restoration.")
    }

    // MARK: - Playback session

    func testPositionUpdatesAreCoalescedBelowToleranceThreshold() {
        let store = AppRestorationStore(defaults: defaults, storageKey: storageKey, writeDebounce: 0)
        let item = ArchiveItem(
            audioFile1: "https://example.invalid/a.mp3",
            audioFile2: "",
            audioFile3: "",
            sendungTitel: "Show",
            untertitelSendung: "",
            terminID: 42,
            terminSlug: "show-1",
            sendungSlug: "show",
            sendungID: 1,
            datum: "2026-05-08",
            datumDe: "08.05.2026",
            startTime: "20:00",
            endTime: "22:00",
            untertitelTermin: ""
        )
        let session = AppRestorationState.PlaybackSession(
            terminID: 42,
            position: 100,
            duration: 3600,
            wasPlaying: false,
            savedAt: Date(),
            item: item
        )
        store.setLastPlaybackSession(session)

        // Sub-second drift sollte den Snapshot nicht erneut markieren.
        store.updatePlaybackPosition(100.4, duration: 3600, wasPlaying: false)
        XCTAssertEqual(store.validLastPlaybackSession?.position, 100, "Tiny position drift must be ignored to avoid write storms.")

        // Größere Änderung muss übernommen werden.
        store.updatePlaybackPosition(150, duration: 3600, wasPlaying: true)
        XCTAssertEqual(store.validLastPlaybackSession?.position, 150)
        XCTAssertEqual(store.validLastPlaybackSession?.wasPlaying, true)
    }

    func testIgnoresSessionWithoutPlayableURLs() {
        let store = AppRestorationStore(defaults: defaults, storageKey: storageKey, writeDebounce: 0)
        let item = ArchiveItem(
            audioFile1: "",
            audioFile2: "",
            audioFile3: "",
            sendungTitel: "Show",
            untertitelSendung: "",
            terminID: 7,
            terminSlug: "s",
            sendungSlug: "s",
            sendungID: nil,
            datum: "",
            datumDe: "",
            startTime: "",
            endTime: "",
            untertitelTermin: ""
        )
        let session = AppRestorationState.PlaybackSession(
            terminID: 7,
            position: 0,
            duration: 0,
            wasPlaying: false,
            savedAt: Date(),
            item: item
        )
        store.setLastPlaybackSession(session)
        XCTAssertNil(store.validLastPlaybackSession, "Sessions without any audio URL must be skipped on restore.")
    }

    // MARK: - Navigation routes

    func testNavigationRoutesPersistAndReload() {
        let store = AppRestorationStore(defaults: defaults, storageKey: storageKey, writeDebounce: 0)
        let routes: [AppRestorationState.DeepRoute] = [
            .favoriteEpisodes,
            .show(slug: "show-foo", title: "Foo", id: 99)
        ]
        store.setFavoritesPath(routes)
        store.flushNow()

        let reloaded = AppRestorationStore(defaults: defaults, storageKey: storageKey, writeDebounce: 0)
        XCTAssertEqual(reloaded.validNavigationRoutes.favorites, routes)
    }

    // MARK: - Scroll anchors removed
    // Die Scroll-Anker-Wiederherstellung wurde entfernt; dieser Test entfällt.

    // MARK: - Version mismatch

    func testIncompatibleVersionResetsToDefaults() {
        // Manuell einen Datensatz mit unbekannter Version schreiben — der Store muss ihn verwerfen, ohne zu crashen.
        struct IncompatiblePayload: Encodable {
            let version: Int
            let savedAt: Date
            let unknownField: String
        }
        let payload = IncompatiblePayload(version: 999, savedAt: Date(), unknownField: "x")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(payload)
        defaults.set(data, forKey: storageKey)

        let store = AppRestorationStore(defaults: defaults, storageKey: storageKey, writeDebounce: 0)
        XCTAssertNil(store.validSelectedRoot)
        XCTAssertNil(store.validLastPlaybackSession)
        XCTAssertEqual(store.validNavigationRoutes, AppRestorationState.NavigationRoutes())
    }
}
