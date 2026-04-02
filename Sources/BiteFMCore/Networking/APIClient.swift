import Foundation
import os
import SwiftData

@MainActor
public class APIClient: ObservableObject {
    public static let shared = APIClient()

    /// Abmelde-Dialog vom Root trennen (kein `@Published`): vermeidet AttributeGraph-Zyklen Alert ↔ ObservableObject.
    public static let requestLogoutConfirmationNotification = Notification.Name("BiteFM.requestLogoutConfirmation")
    
    @Published var isLoggedIn = false
    @Published var shows: [Show] = []
    @Published var favoriteSlugs: Set<String> = []
    /// Episode (show) IDs from `get_favorites` → `shows[]`.
    @Published var favoriteShowIDs: Set<Int> = []
    @Published var favoriteShowItems: [FavoriteShowItem] = []
    @Published var favoriteTrackItems: [FavoriteTrackItem] = []
    /// Local or merged „Favorisiert am“-Zeitstempel pro Episoden-`show.id` (SwiftData + API).
    @Published var favoriteShowFavoritedAt: [Int: Date] = [:]
    @Published var listenedShowIDs: Set<Int> = []
    @Published var liveMetadata: LiveMetadataResponse?
    @Published var errorMessage: String?
    @Published var didFinishInitialBootstrap = false
    /// Set when a main list fetch fails with a connectivity error and the UI might be empty; cleared on any successful list refresh.
    @Published public private(set) var lastListRefreshFailedWithoutNetwork = false

    var modelContainer: ModelContainer?

    public static func isLikelyNetworkConnectivityFailure(_ error: Error) -> Bool {
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost,
                 .timedOut, .dnsLookupFailed, .internationalRoamingOff, .callIsActive:
                return true
            default:
                break
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed,
                 NSURLErrorCannotFindHost, NSURLErrorTimedOut, NSURLErrorDNSLookupFailed:
                return true
            default:
                break
            }
        }
        return false
    }

    public func requestLogoutConfirmation() {
        NotificationCenter.default.post(name: Self.requestLogoutConfirmationNotification, object: nil)
    }
    
    /// Ab wann eine neue Historie-Abfrage beim Start der Wiedergabe sinnvoll ist (letzte erfolgreiche Abfrage älter als das).
    private let listeningHistoryPlaybackStaleInterval: TimeInterval = 30 * 60
    
    private static let listeningHistoryLastSuccessKey = "listeningHistoryLastFetchSuccessAt"
    
    private var broadcastDetailsCache: [Int: BroadcastDetail] = [:]
    private var pollingTask: Task<Void, Never>?
    private var archivePollingTask: Task<Void, Never>?
    private var pendingHistoryVerificationShowID: Int?
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        return URLSession(configuration: config)
    }()

    private func agentDebugLog(
        runId: String = "initial",
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: Any]
    ) {
        let payload: [String: Any] = [
            "sessionId": "d22446",
            "runId": runId,
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let json = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var line = json
        line.append(0x0A)
        let url = URL(fileURLWithPath: "/Users/tf/Nextcloud/gitfolder/BiteFM/.cursor/debug-d22446.log")
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } catch {
                try? handle.close()
            }
        } else {
            try? line.write(to: url)
        }
    }
    
    public init() {
        // Check if we have saved credentials to be "logged in" immediately
        if let username = UserDefaults.standard.string(forKey: "savedUsername"),
           let _ = KeychainHelper.readPassword(account: username) {
            self.isLoggedIn = true
        }
        // Do NOT start live metadata polling globally anymore
    }
    
    func setup(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        LogManager.shared.log("APIClient setup with ModelContainer", type: .debug)
        
        // Initial UI state should come from the local cache first.
        // Remote refreshes run afterwards so launch is not gated on the network.
        Task {
            let context = modelContainer.mainContext
            
            // Load Favorites
            let favoritesDescriptor = FetchDescriptor<StoredFavoriteBroadcast>()
            if let storedFavorites = try? context.fetch(favoritesDescriptor) {
                self.favoriteSlugs = Set(storedFavorites.map { $0.sendungSlug })
                LogManager.shared.log("Loaded \(self.favoriteSlugs.count) favorite slugs from disk", type: .debug)
            }
            
            let favoriteShowsDescriptor = FetchDescriptor<StoredFavoriteShow>()
            if let storedShowFavorites = try? context.fetch(favoriteShowsDescriptor) {
                self.favoriteShowIDs = Set(storedShowFavorites.map { $0.showID })
                self.favoriteShowFavoritedAt = Dictionary(uniqueKeysWithValues: storedShowFavorites.map { ($0.showID, $0.createdAt) })
                LogManager.shared.log("Loaded \(self.favoriteShowIDs.count) favorite episode IDs from disk", type: .debug)
            }
            
            // Load History
            let historyDescriptor = FetchDescriptor<StoredListeningHistoryEntry>()
            if let storedHistory = try? context.fetch(historyDescriptor) {
                self.listenedShowIDs = Set(storedHistory.map { $0.showID })
                LogManager.shared.log("Loaded \(self.listenedShowIDs.count) listening history entries from disk", type: .debug)
            }
            
            // Load Shows
            let showsDescriptor = FetchDescriptor<StoredShow>(sortBy: [SortDescriptor(\.titel)])
            if let storedShows = try? context.fetch(showsDescriptor) {
                self.shows = storedShows.map { $0.toShow() }
                LogManager.shared.log("Loaded \(self.shows.count) shows from disk", type: .debug)
            }
            
            // Cached data is ready; unblock the UI before remote sync starts.
            didFinishInitialBootstrap = true

            // Remote refresh runs in the background so startup stays responsive.
            if isLoggedIn {
                Task {
                    await fetchFavorites(modelContext: context)
                    await fetchListeningHistory(modelContext: context)
                }
            }

            // Archive stays on-demand in ArchiveNew instead of loading at app start.
            startFavoritesPolling()
            startHistoryPolling()
        }
    }
    
    private var favoritesPollingTask: Task<Void, Never>?
    private var historyPollingTask: Task<Void, Never>?

    /// Nur nach `pauseDeferredPolling` (iOS: App war im Hintergrund). Beim ersten Cold-Start-`.active` bleibt `false`, damit kein zweiter Start die Requests aus `setup` abbricht.
    private var shouldRestartDeferredPollingAfterReturningFromBackground = false
    
    func startFavoritesPolling() {
        favoritesPollingTask?.cancel()
        favoritesPollingTask = Task {
            while !Task.isCancelled {
                // Erst warten: initiale Loads laufen im `setup`-Task bzw. nach Login — vermeidet parallele Doppel-Requests.
                try? await Task.sleep(nanoseconds: 60 * 60 * 1_000_000_000)
                guard !Task.isCancelled else { break }
                if isLoggedIn {
                    let context = modelContainer?.mainContext
                    await fetchFavorites(modelContext: context)
                }
            }
        }
    }
    
    func startHistoryPolling() {
        historyPollingTask?.cancel()
        historyPollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3 * 60 * 60 * 1_000_000_000)
                guard !Task.isCancelled else { break }
                if isLoggedIn {
                    let context = modelContainer?.mainContext
                    await fetchHistory(modelContext: context)
                }
            }
        }
    }

    // MARK: - Background / lifecycle (esp. iOS)

    /// Cancels long-interval polling tasks while the app is not active (saves battery / aligns with iOS lifecycle).
    func pauseDeferredPolling() {
        shouldRestartDeferredPollingAfterReturningFromBackground = true
        favoritesPollingTask?.cancel()
        favoritesPollingTask = nil
        historyPollingTask?.cancel()
        historyPollingTask = nil
    }

    /// Erst nach echtem Background → Foreground: Polling neu starten und Favoriten/Historie einmal refreshen.
    /// Archivdaten werden nur noch on-demand in `ArchiveNew` geladen.
    func resumeDeferredPollingIfConfigured() {
        guard modelContainer != nil else { return }
        guard shouldRestartDeferredPollingAfterReturningFromBackground else { return }
        shouldRestartDeferredPollingAfterReturningFromBackground = false
        startFavoritesPolling()
        startHistoryPolling()
        guard isLoggedIn else { return }
        Task {
            let ctx = modelContainer?.mainContext
            await fetchFavorites(modelContext: ctx)
            await fetchListeningHistory(modelContext: ctx)
        }
    }
    
    private func dateOfLastListeningHistoryFetchSuccess() -> Date? {
        let t = UserDefaults.standard.double(forKey: Self.listeningHistoryLastSuccessKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    
    private func recordListeningHistoryFetchSuccess() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.listeningHistoryLastSuccessKey)
    }
    
    /// Ruft die Hörhistorie ab, wenn der Nutzer eingeloggt ist und die letzte erfolgreiche Abfrage älter als 30 Minuten ist (oder noch nie stattfand).
    func refreshListeningHistoryIfStale() async {
        guard isLoggedIn else { return }
        let now = Date()
        if let last = dateOfLastListeningHistoryFetchSuccess(),
           now.timeIntervalSince(last) < listeningHistoryPlaybackStaleInterval {
            return
        }
        let context = modelContainer?.mainContext
        await fetchListeningHistory(modelContext: context)
    }
    
    // Helper to call fetchListeningHistory with correct naming
    private func fetchHistory(modelContext: ModelContext? = nil) async {
        await fetchListeningHistory(modelContext: modelContext)
    }
    
    func isFavorite(item: ArchiveItem) -> Bool {
        FavoriteStateLogic.isFavoriteArchiveItem(
            sendungSlug: item.sendungSlug,
            terminSlug: item.terminSlug,
            sendungTitel: item.sendungTitel,
            terminID: item.terminID,
            favoriteSlugs: favoriteSlugs,
            favoriteShowIDs: favoriteShowIDs
        )
    }
    
    func isFavorite(show: Show) -> Bool {
        return isFavorite(slug: show.slug, title: show.titel)
    }
    
    func isFavorite(slug: String, title: String) -> Bool {
        FavoriteStateLogic.isFavoriteBroadcast(slug: slug, title: title, favoriteSlugs: favoriteSlugs)
    }
    
    func resolvedFavoritedAt(for item: FavoriteShowItem) -> Date {
        item.favoritedAt ?? favoriteShowFavoritedAt[item.show.id] ?? .distantPast
    }
    
    func isEpisodeFavorite(item: ArchiveItem) -> Bool {
        FavoriteStateLogic.isEpisodeFavorite(
            terminID: item.terminID,
            terminSlug: item.terminSlug,
            favoriteShowIDs: favoriteShowIDs,
            favoriteSlugs: favoriteSlugs
        )
    }
    
    func isPlayed(item: ArchiveItem) -> Bool {
        return listenedShowIDs.contains(item.terminID)
    }
    
    func isPlayed(broadcastID: Int) -> Bool {
        return listenedShowIDs.contains(broadcastID)
    }
    
    /// Lädt die Hörhistorie vom Server neu (`listeningHistoryEntries.php`). Die App sendet keinen eigenen „als gehört markieren“-Request;
    /// `listenedShowIDs` spiegelt nur, was die API zurückgibt (`show_id` = Termin-ID der Ausgabe).
    func markAsPlayed(item: ArchiveItem) async {
        pendingHistoryVerificationShowID = item.terminID
        // #region agent log
        agentDebugLog(
            hypothesisId: "H1",
            location: "APIClient.swift:275",
            message: "mark_as_played_invoked",
            data: [
                "terminID": item.terminID,
                "alreadyInLocalHistory": listenedShowIDs.contains(item.terminID),
                "isLoggedIn": isLoggedIn,
                "hasSavedUsername": UserDefaults.standard.string(forKey: "savedUsername") != nil,
                "hasSavedPassword": UserDefaults.standard.string(forKey: "savedUsername").flatMap { KeychainHelper.readPassword(account: $0) } != nil
            ]
        )
        // #endregion
        LogManager.shared.log("Syncing listening history after play: \(item.sendungTitel) (ID: \(item.terminID))", type: .info)
        
        if let context = modelContainer.map({ ModelContext($0) }) {
            await fetchListeningHistory(modelContext: context)
        } else {
            await fetchListeningHistory()
        }
    }
    
    /// Task or URLSession cancellation (e.g. polling task cancelled on scene changes) must not surface as a user-facing failure.
    private func isBenignCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }
    
    private func performRequest(for request: URLRequest, retryOnAuthFailure: Bool = true) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, 
               (httpResponse.statusCode == 401 || httpResponse.statusCode == 403),
               retryOnAuthFailure {
                LogManager.shared.log("Session expired or unauthorized (Code: \(httpResponse.statusCode)). Attempting silent re-login...", type: .error)
                
                if let username = UserDefaults.standard.string(forKey: "savedUsername"),
                   let password = KeychainHelper.readPassword(account: username) {
                    
                    let success = await login(username: username, password: password, isAutoLogin: true)
                    if success {
                        LogManager.shared.log("Silent re-login successful. Retrying original request...", type: .info)
                        // Retry once WITHOUT further retries on auth failure to avoid infinite loop
                        return try await performRequest(for: request, retryOnAuthFailure: false)
                    } else {
                        LogManager.shared.log("Silent re-login FAILED. User must login manually.", type: .error)
                        isLoggedIn = false
                    }
                } else {
                    LogManager.shared.log("No credentials found for silent re-login.", type: .error)
                    isLoggedIn = false
                }
            }
            
            return (data, response)
        } catch {
            if isBenignCancellation(error) {
                LogManager.shared.log("performRequest cancelled", type: .debug)
            } else {
                LogManager.shared.log("Network error in performRequest: \(error.localizedDescription)", type: .error)
            }
            throw error
        }
    }

    func fetchListeningHistory(modelContext: ModelContext? = nil) async {
        guard let url = URL(string: "https://www.byte.fm/mobile-apps/v2/listeningHistoryEntries.php") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("BiteFM/5.0.23 (iPad; iOS 26.3; Scale/2.00)", forHTTPHeaderField: "User-Agent")
        
        // Add Basic Auth if we have credentials
        if let username = UserDefaults.standard.string(forKey: "savedUsername"),
           let password = KeychainHelper.readPassword(account: username) {
            let authString = "\(username):\(password)"
            if let authData = authString.data(using: .utf8) {
                let base64Auth = authData.base64EncodedString()
                request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
            }
        }
        
        LogManager.shared.log("Fetching listening history from \(url.absoluteString)...", type: .info)
        let trackedShowID = pendingHistoryVerificationShowID
        // #region agent log
        agentDebugLog(
            hypothesisId: "H1",
            location: "APIClient.swift:351",
            message: "listening_history_request_started",
            data: [
                "method": request.httpMethod ?? "",
                "url": url.absoluteString,
                "hasAuthorization": request.value(forHTTPHeaderField: "Authorization") != nil,
                "trackedShowID": trackedShowID ?? -1
            ]
        )
        // #endregion
        
        do {
            let (data, response) = try await performRequest(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                LogManager.shared.log("History response status code: \(httpResponse.statusCode)", type: .debug)
                
                if httpResponse.statusCode == 200 {
                    let decoder = JSONDecoder()
                    do {
                        let historyResponse = try decoder.decode(ListeningHistoryResponse.self, from: data)
                        LogManager.shared.log("Successfully decoded history: \(historyResponse.data.count) entries", type: .info)
                        
                        let ids = Set(historyResponse.data.map { $0.showID })
                        self.listenedShowIDs = ids
                        self.recordListeningHistoryFetchSuccess()
                        // #region agent log
                        agentDebugLog(
                            hypothesisId: trackedShowID == nil ? "H1" : "H4",
                            location: "APIClient.swift:370",
                            message: "listening_history_response_decoded",
                            data: [
                                "statusCode": httpResponse.statusCode,
                                "responseCount": historyResponse.data.count,
                                "trackedShowID": trackedShowID ?? -1,
                                "containsTrackedShow": trackedShowID.map(ids.contains) ?? false
                            ]
                        )
                        // #endregion
                        if trackedShowID != nil {
                            pendingHistoryVerificationShowID = nil
                        }
                        
                        if let context = modelContext {
                            try await syncListeningHistoryWithDatabase(items: historyResponse.data, context: context)
                        }
                    } catch {
                        LogManager.shared.log("FAILED to decode listening history: \(error)", type: .error)
                    }
                }
            }
        } catch {
            if isBenignCancellation(error) {
                LogManager.shared.log("Listening history fetch cancelled", type: .debug)
                return
            }
            // #region agent log
            agentDebugLog(
                hypothesisId: trackedShowID == nil ? "H1" : "H4",
                location: "APIClient.swift:393",
                message: "listening_history_request_failed",
                data: [
                    "trackedShowID": trackedShowID ?? -1,
                    "error": error.localizedDescription
                ]
            )
            // #endregion
            if trackedShowID != nil {
                pendingHistoryVerificationShowID = nil
            }
            LogManager.shared.log("Failed to fetch listening history: \(error.localizedDescription)", type: .error)
        }
    }
    
    private func syncListeningHistoryWithDatabase(items: [ListeningHistoryEntry], context: ModelContext) async throws {
        // Use a more stable update pattern to avoid SwiftData fatal errors (like "remapped to a temporary identifier")
        let descriptor = FetchDescriptor<StoredListeningHistoryEntry>()
        let existingEntries = try context.fetch(descriptor)
        let existingMap = Dictionary(uniqueKeysWithValues: existingEntries.map { ($0.showID, $0) })
        
        let newItemIDs = Set(items.map { $0.showID })
        
        // 1. Delete entries that are no longer present
        for (id, entry) in existingMap {
            if !newItemIDs.contains(id) {
                context.delete(entry)
            }
        }
        
        // 2. Update existing or insert new entries
        for item in items {
            if let existing = existingMap[item.showID] {
                existing.dateString = item.date
            } else {
                let newEntry = StoredListeningHistoryEntry(showID: item.showID, dateString: item.date)
                context.insert(newEntry)
            }
        }
        
        try context.save()
    }
    
    func fetchFavorites(modelContext: ModelContext? = nil) async {
        guard let url = URL(string: "https://www.byte.fm/api/v1/friends/get_favorites/") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("BiteFM/5.0.23 (iPad; iOS 26.3; Scale/2.00)", forHTTPHeaderField: "User-Agent")
        
        // Add Basic Auth if we have credentials
        if let username = UserDefaults.standard.string(forKey: "savedUsername"),
           let password = KeychainHelper.readPassword(account: username) {
            let authString = "\(username):\(password)"
            if let authData = authString.data(using: .utf8) {
                let base64Auth = authData.base64EncodedString()
                request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
            }
        }
        
        LogManager.shared.log("Fetching favorites from \(url.absoluteString)...", type: .info)
        
        do {
            let (data, response) = try await performRequest(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                LogManager.shared.log("Favorites response status code: \(httpResponse.statusCode)", type: .debug)
                
                if httpResponse.statusCode == 200 {
                    let decoder = JSONDecoder()
                    
                    do {
                        let favoritesResponse = try decoder.decode(FavoritesResponse.self, from: data)
                        LogManager.shared.log("Successfully decoded FavoritesResponse. Shows: \(favoritesResponse.shows.count), tracks: \(favoritesResponse.tracks.count)", type: .info)
                        lastListRefreshFailedWithoutNetwork = false

                        // Extract all broadcast slugs and titles (Sendungen)
                        var slugs = Set<String>()
                        var syncItems: [FavoriteBroadcast] = []
                        
                        let addBroadcast = { (info: BroadcastInfo) in
                            let slug = info.slug.lowercased()
                            slugs.insert(slug)
                            slugs.insert(info.title)
                            
                            if !syncItems.contains(where: { $0.sendungSlug == slug }) {
                                syncItems.append(FavoriteBroadcast(sendungTitel: info.title, sendungSlug: slug))
                            }
                        }
                        
                        for item in favoritesResponse.broadcasts { addBroadcast(item.broadcast) }
                        for item in favoritesResponse.shows { addBroadcast(item.broadcast) }
                        for item in favoritesResponse.tracks {
                            if let broadcastInfo = item.broadcast { addBroadcast(broadcastInfo) }
                        }
                        
                        let episodeIDs = Set(favoritesResponse.shows.map { $0.show.id })
                        
                        self.favoriteSlugs = slugs
                        self.favoriteShowIDs = episodeIDs
                        self.favoriteShowItems = favoritesResponse.shows
                        self.favoriteTrackItems = favoritesResponse.tracks
                        
                        if let context = modelContext {
                            try await syncFavoritesWithDatabase(items: syncItems, context: context)
                            try await syncFavoriteShowsWithDatabase(showItems: favoritesResponse.shows, context: context)
                            let rows = try context.fetch(FetchDescriptor<StoredFavoriteShow>())
                            self.favoriteShowFavoritedAt = Dictionary(uniqueKeysWithValues: rows.map { ($0.showID, $0.createdAt) })
                        }
                    } catch {
                        LogManager.shared.log("FAILED to decode FavoritesResponse: \(error)", type: .error)
                    }
                }
            }
        } catch {
            if isBenignCancellation(error) {
                LogManager.shared.log("Favorites fetch cancelled", type: .debug)
                return
            }
            LogManager.shared.log("Failed to fetch favorites: \(error.localizedDescription)", type: .error)
            if Self.isLikelyNetworkConnectivityFailure(error) {
                lastListRefreshFailedWithoutNetwork = true
            }
        }
    }
    
    private func syncFavoritesWithDatabase(items: [FavoriteBroadcast], context: ModelContext) async throws {
        // Use a stable update pattern to avoid SwiftData fatal errors
        let descriptor = FetchDescriptor<StoredFavoriteBroadcast>()
        let existingEntries = try context.fetch(descriptor)
        let existingMap = Dictionary(uniqueKeysWithValues: existingEntries.map { ($0.sendungSlug, $0) })
        
        let newItemSlugs = Set(items.map { $0.sendungSlug })
        
        // 1. Delete items no longer in the list
        for (slug, entry) in existingMap {
            if !newItemSlugs.contains(slug) {
                context.delete(entry)
            }
        }
        
        // 2. Update existing or insert new
        for item in items {
            if let existing = existingMap[item.sendungSlug] {
                existing.sendungTitel = item.sendungTitel
            } else {
                let newEntry = StoredFavoriteBroadcast(from: item)
                context.insert(newEntry)
            }
        }
        
        try context.save()
    }
    
    private func syncFavoriteShowsWithDatabase(showItems: [FavoriteShowItem], context: ModelContext) async throws {
        let serverIDs = Set(showItems.map { $0.show.id })
        let descriptor = FetchDescriptor<StoredFavoriteShow>()
        let existingEntries = try context.fetch(descriptor)
        let existingMap = Dictionary(uniqueKeysWithValues: existingEntries.map { ($0.showID, $0) })
        
        for item in showItems {
            let sid = item.show.id
            if existingMap[sid] != nil {
                continue
            }
            let created = item.favoritedAt ?? Date()
            context.insert(StoredFavoriteShow(showID: sid, createdAt: created))
        }
        
        for (sid, entry) in existingMap where !serverIDs.contains(sid) {
            context.delete(entry)
        }
        
        try context.save()
    }
    
    private struct FavoriteUICache {
        let favoriteSlugs: Set<String>
        let favoriteShowIDs: Set<Int>
        let favoriteShowItems: [FavoriteShowItem]
        let favoriteTrackItems: [FavoriteTrackItem]
        let favoriteShowFavoritedAt: [Int: Date]
    }
    
    private func captureFavoriteUICache() -> FavoriteUICache {
        FavoriteUICache(
            favoriteSlugs: favoriteSlugs,
            favoriteShowIDs: favoriteShowIDs,
            favoriteShowItems: favoriteShowItems,
            favoriteTrackItems: favoriteTrackItems,
            favoriteShowFavoritedAt: favoriteShowFavoritedAt
        )
    }
    
    private func restoreFavoriteUICache(_ cache: FavoriteUICache) {
        favoriteSlugs = cache.favoriteSlugs
        favoriteShowIDs = cache.favoriteShowIDs
        favoriteShowItems = cache.favoriteShowItems
        favoriteTrackItems = cache.favoriteTrackItems
        favoriteShowFavoritedAt = cache.favoriteShowFavoritedAt
    }
    
    func toggleFavoriteBroadcast(slug: String, displayTitle: String = "") async {
        let snapshot = captureFavoriteUICache()
        let lower = slug.lowercased()
        let was = FavoriteStateLogic.isFavoriteBroadcast(slug: slug, title: displayTitle, favoriteSlugs: favoriteSlugs)
        if was {
            favoriteSlugs.remove(lower)
            if !displayTitle.isEmpty {
                favoriteSlugs.remove(displayTitle)
            }
        } else {
            favoriteSlugs.insert(lower)
            if !displayTitle.isEmpty {
                favoriteSlugs.insert(displayTitle)
            }
        }
        
        let success = await toggleChangeFavorite(queryItems: [URLQueryItem(name: "broadcast_slug", value: slug)])
        if !success {
            restoreFavoriteUICache(snapshot)
        }
    }
    
    func toggleFavoriteEpisode(showID: Int) async {
        let snapshot = captureFavoriteUICache()
        let was = favoriteShowIDs.contains(showID)
        if was {
            favoriteShowIDs.remove(showID)
            favoriteShowItems.removeAll { $0.show.id == showID }
        } else {
            favoriteShowIDs.insert(showID)
        }
        
        let success = await toggleChangeFavorite(queryItems: [URLQueryItem(name: "show_id", value: String(showID))])
        if !success {
            restoreFavoriteUICache(snapshot)
        }
    }
    
    /// Toggles favorite for a track (`track_id`); `trackID` is the favorite row id from `get_favorites` → `tracks[].id`.
    func toggleFavoriteTrack(trackID: Int, cachedItem: FavoriteTrackItem? = nil) async {
        let snapshot = captureFavoriteUICache()
        let was = favoriteTrackItems.contains(where: { $0.id == trackID })
        if was {
            favoriteTrackItems.removeAll { $0.id == trackID }
        } else if let cached = cachedItem {
            favoriteTrackItems.insert(cached, at: 0)
        }
        
        let success = await toggleChangeFavorite(queryItems: [URLQueryItem(name: "track_id", value: String(trackID))])
        if !success {
            restoreFavoriteUICache(snapshot)
        }
    }
    
    func isFavoriteTrackRow(id: Int) -> Bool {
        favoriteTrackItems.contains(where: { $0.id == id })
    }
    
    private func toggleChangeFavorite(queryItems: [URLQueryItem]) async -> Bool {
        guard isLoggedIn else {
            LogManager.shared.log("toggleChangeFavorite: not logged in", type: .debug)
            return false
        }
        guard var components = URLComponents(string: "https://www.byte.fm/ajax/change-favorite/") else { return false }
        components.queryItems = queryItems
        
        guard let url = components.url else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("BiteFM/5.0.23 (iPad; iOS 26.3; Scale/2.00)", forHTTPHeaderField: "User-Agent")
        
        if let username = UserDefaults.standard.string(forKey: "savedUsername"),
           let password = KeychainHelper.readPassword(account: username) {
            let authString = "\(username):\(password)"
            if let authData = authString.data(using: .utf8) {
                let base64Auth = authData.base64EncodedString()
                request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
            }
        }
        
        do {
            let (data, response) = try await performRequest(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                LogManager.shared.log("change-favorite: bad HTTP", type: .error)
                return false
            }
            let decoded = try JSONDecoder().decode(ChangeFavoriteResponse.self, from: data)
            if decoded.error != 0 {
                LogManager.shared.log("change-favorite: error=\(decoded.error) status=\(decoded.status)", type: .error)
                return false
            }
            if let container = modelContainer {
                await fetchFavorites(modelContext: container.mainContext)
            } else {
                await fetchFavorites()
            }
            return true
        } catch {
            LogManager.shared.log("change-favorite failed: \(error.localizedDescription)", type: .error)
            return false
        }
    }
    
    func startLiveMetadataPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                await fetchLiveMetadata()
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000) // Poll every 60 seconds
            }
        }
    }
    
    func stopLiveMetadataPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func startArchivePolling() {
        archivePollingTask?.cancel()
        archivePollingTask = Task {
            while !Task.isCancelled {
                if isLoggedIn {
                    let context = modelContainer?.mainContext
                    await fetchArchive(modelContext: context)
                }
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000) // 30 minutes
            }
        }
    }
    
    func fetchLiveMetadata() async {
        guard let url = URL(string: "https://www.byte.fm/api/v1/song-history/") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("BiteFM/5.0.23 (iPad; iOS 26.3; Scale/2.00)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await session.data(for: request)
            let metadata = try JSONDecoder().decode(LiveMetadataResponse.self, from: data)
            // Gleicher Inhalt: kein @Published-Feuer → weniger Attribut-Invalidierungen (LiveView + PlayerBarView).
            guard metadata != liveMetadata else { return }
            self.liveMetadata = metadata
            
            // Update Now Playing if live is active
            if AudioPlayerManager.shared.isLive {
                AudioPlayerManager.shared.updateNowPlayingWithMetadata(metadata)
            }
        } catch {
            if isBenignCancellation(error) {
                LogManager.shared.log("Live metadata fetch cancelled", type: .debug)
                return
            }
            LogManager.shared.log("Failed to fetch live metadata: \(error)", type: .error)
        }
    }
    
    func autoLogin() async {
        guard let username = UserDefaults.standard.string(forKey: "savedUsername"),
              let password = KeychainHelper.readPassword(account: username) else {
            return
        }
        await login(username: username, password: password, isAutoLogin: true)
    }
    
    @discardableResult
    func login(username: String, password: String, isAutoLogin: Bool = false) async -> Bool {
        guard let url = URL(string: "https://www.byte.fm/mobile-apps/v2/verifyUsernamePassword.php") else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("BiteFM/5.0.23 (iPad; iOS 26.3; Scale/2.00)", forHTTPHeaderField: "User-Agent")
        
        let bodyString = "username=\(username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&password=\(password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        request.httpBody = bodyString.data(using: .utf8)
        
        do {
            let (_, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                // If login succeeds, the session automatically stores cookies.
                errorMessage = nil
                
                // Switch the UI immediately after successful credential verification.
                isLoggedIn = true
                didFinishInitialBootstrap = true

                // Keep polling aligned with the new authenticated session.
                startFavoritesPolling()
                startHistoryPolling()

                // Refresh authenticated data in the background so the UI can appear immediately.
                Task {
                    if let container = self.modelContainer {
                        let context = container.mainContext
                        await self.fetchFavorites(modelContext: context)
                        await self.fetchListeningHistory(modelContext: context)
                    } else {
                        await self.fetchFavorites()
                        await self.fetchListeningHistory()
                    }
                }

                // Fetch shows if empty
                if shows.isEmpty {
                    if let container = modelContainer {
                        await fetchShows(modelContext: container.mainContext)
                    } else {
                        await fetchShows()
                    }
                }
                return true
            } else {
                isLoggedIn = false
                if !isAutoLogin {
                    errorMessage = "Login fehlgeschlagen"
                }
                return false
            }
        } catch {
            if isBenignCancellation(error) {
                return false
            }
            isLoggedIn = false
            if !isAutoLogin {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }
    
    func logout() {
        if let username = UserDefaults.standard.string(forKey: "savedUsername") {
            KeychainHelper.deletePassword(account: username)
        }
        UserDefaults.standard.removeObject(forKey: "savedUsername")
        isLoggedIn = false
        lastListRefreshFailedWithoutNetwork = false
        // Clear favorites and history
        favoriteSlugs.removeAll()
        favoriteShowIDs.removeAll()
        favoriteShowItems.removeAll()
        favoriteTrackItems.removeAll()
        favoriteShowFavoritedAt.removeAll()
        listenedShowIDs.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.listeningHistoryLastSuccessKey)
        
        // Clear favorites and history from database
        if let container = modelContainer {
            let context = ModelContext(container)
            if let favorites = try? context.fetch(FetchDescriptor<StoredFavoriteBroadcast>()) {
                for fav in favorites {
                    context.delete(fav)
                }
            }
            if let showFavs = try? context.fetch(FetchDescriptor<StoredFavoriteShow>()) {
                for fav in showFavs {
                    context.delete(fav)
                }
            }
            if let history = try? context.fetch(FetchDescriptor<StoredListeningHistoryEntry>()) {
                for entry in history {
                    context.delete(entry)
                }
            }
            if let archiveItems = try? context.fetch(FetchDescriptor<StoredArchiveItem>()) {
                for item in archiveItems {
                    context.delete(item)
                }
            }
            #if os(iOS)
            IOSDownloadManager.purgeAllOnLogout(container: container)
            #endif
            try? context.save()
        }
        
        // Clear cookies
        session.configuration.httpCookieStorage?.removeCookies(since: .distantPast)
    }
    
    func fetchArchive(modelContext: ModelContext? = nil) async {
        guard let url = URL(string: "https://www.byte.fm/mobile-apps/v2/archiveSendungenNew.php") else { 
            LogManager.shared.log("Invalid Archive URL", type: .error)
            return 
        }
        
        LogManager.shared.log("Fetching archive (Neu im Archiv) from \(url.absoluteString)...", type: .info)
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("BiteFM/5.0.23 (iPad; iOS 26.3; Scale/2.00)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await performRequest(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                LogManager.shared.log("Archive response status: \(httpResponse.statusCode)", type: .debug)
                if httpResponse.statusCode == 200 {
                    do {
                        let items = try JSONDecoder().decode([ArchiveItem].self, from: data)
                        LogManager.shared.log("Successfully fetched \(items.count) archive items.", type: .info)
                        lastListRefreshFailedWithoutNetwork = false
                        if let context = modelContext {
                            try await syncWithDatabase(items: items, context: context)
                        }
                    } catch {
                        LogManager.shared.log("FAILED to decode archive: \(error)", type: .error)
                    }
                } else {
                    LogManager.shared.log("Archive request failed with status code: \(httpResponse.statusCode)", type: .error)
                }
            }
        } catch {
            if isBenignCancellation(error) {
                LogManager.shared.log("Archive fetch cancelled (expected when polling stops)", type: .debug)
                return
            }
            LogManager.shared.log("FAILED to fetch archive: \(error.localizedDescription)", type: .error)
            errorMessage = "Failed to fetch archive: \(error.localizedDescription)"
            if Self.isLikelyNetworkConnectivityFailure(error) {
                lastListRefreshFailedWithoutNetwork = true
            }
        }
    }

    private func syncWithDatabase(items: [ArchiveItem], context: ModelContext) async throws {
        // Use a stable update pattern to avoid SwiftData fatal errors
        let descriptor = FetchDescriptor<StoredArchiveItem>()
        let existingEntries = try context.fetch(descriptor)
        let existingMap = Dictionary(uniqueKeysWithValues: existingEntries.map { ($0.terminID, $0) })
        
        LogManager.shared.log("Syncing with database: \(items.count) items from server, \(existingEntries.count) currently in database.", type: .info)
        
        // 1. Update existing or insert new items
        for item in items {
            if let existing = existingMap[item.terminID] {
                // Update properties to ensure they're in sync
                existing.audioFile1 = item.audioFile1
                existing.audioFile2 = item.audioFile2
                existing.audioFile3 = item.audioFile3
                existing.sendungTitel = item.sendungTitel
                existing.untertitelSendung = item.untertitelSendung
                existing.terminSlug = item.terminSlug
                existing.sendungSlug = item.sendungSlug
                existing.sendungID = item.sendungID
                existing.datum = item.datum
                existing.datumDe = item.datumDe
                existing.startTime = item.startTime
                existing.endTime = item.endTime
                existing.untertitelTermin = item.untertitelTermin
                // CRITICAL: Update broadcastDate so old items don't get deleted if their date was updated
                existing.broadcastDate = StoredArchiveItem.parseDate(item.datum)
            } else {
                let storedItem = StoredArchiveItem(from: item)
                context.insert(storedItem)
            }
        }
        
        // 2. Cleanup items older than 4 weeks (based on broadcast date)
        let fourWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: Date()) ?? Date()
        
        // Only cleanup older items that are NOT in the current fetch (to be safe)
        let newItemIDs = Set(items.map { $0.terminID })
        let oldItems = existingEntries.filter { $0.broadcastDate < fourWeeksAgo && !newItemIDs.contains($0.terminID) }
        
        if !oldItems.isEmpty {
            LogManager.shared.log("Cleaning up \(oldItems.count) archive items older than 4 weeks (before \(fourWeeksAgo))", type: .info)
            for oldItem in oldItems {
                context.delete(oldItem)
            }
        }
        
        try context.save()
    }
    
    func fetchShows(modelContext: ModelContext? = nil) async {
        guard let url = URL(string: "https://www.byte.fm/mobile-apps/v2/archiveSendungen.php") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("BiteFM/5.0.23 (iPad; iOS 26.3; Scale/2.00)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await performRequest(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let decodedShows = try JSONDecoder().decode([Show].self, from: data)
                self.shows = decodedShows
                lastListRefreshFailedWithoutNetwork = false

                if let context = modelContext {
                    try await syncShowsWithDatabase(items: decodedShows, context: context)
                }
            }
        } catch {
            LogManager.shared.log("Failed to fetch shows: \(error.localizedDescription)", type: .error)
            if Self.isLikelyNetworkConnectivityFailure(error) {
                lastListRefreshFailedWithoutNetwork = true
            }
        }
    }
    
    private func syncShowsWithDatabase(items: [Show], context: ModelContext) async throws {
        // Use a stable update pattern to avoid SwiftData fatal errors
        let descriptor = FetchDescriptor<StoredShow>()
        let existingEntries = try context.fetch(descriptor)
        let existingMap = Dictionary(uniqueKeysWithValues: existingEntries.map { ($0.id, $0) })
        
        let newItemIDs = Set(items.map { $0.id })
        
        // 1. Delete
        for (id, entry) in existingMap {
            if !newItemIDs.contains(id) {
                context.delete(entry)
            }
        }
        
        // 2. Update or insert
        for item in items {
            if let existing = existingMap[item.id] {
                existing.titel = item.titel
                existing.untertitel = item.untertitel
                existing.lastUpdated = Date()
            } else {
                let newEntry = StoredShow(from: item)
                context.insert(newEntry)
            }
        }
        
        try context.save()
    }
    
    func fetchBroadcasts(showSlug: String, page: Int = 1) async -> PaginatedBroadcasts? {
        guard let url = URL(string: "https://www.byte.fm/api/v1/broadcasts/\(showSlug)/?page=\(page)") else { return nil }
        
        LogManager.shared.log("Fetching broadcasts for \(showSlug) from \(url.absoluteString)...", type: .info)
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("BiteFM/5.0.23 (iPad; iOS 26.3; Scale/2.00)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await session.data(for: request)
            let result = try JSONDecoder().decode(PaginatedBroadcasts.self, from: data)
            lastListRefreshFailedWithoutNetwork = false
            return result
        } catch {
            LogManager.shared.log("Failed to fetch broadcasts for \(showSlug): \(error)", type: .error)
            if Self.isLikelyNetworkConnectivityFailure(error) {
                lastListRefreshFailedWithoutNetwork = true
            }
            return nil
        }
    }
    
    func fetchBroadcastDetail(for item: ArchiveItem) async -> BroadcastDetail? {
        if let cached = broadcastDetailsCache[item.id] {
            return cached
        }
        
        guard let url = makeBroadcastDetailURL(for: item) else {
            LogManager.shared.log(
                "Broadcast detail: keine URL (Offline/ungültig?) terminID=\(item.terminID) datum_de=\(item.datumDe) sendung=\(item.sendungSlug) terminSlug=\(item.terminSlug)",
                type: .error
            )
            #if os(iOS)
            if let offline = offlineBroadcastDetailFromStore(terminID: item.terminID) {
                broadcastDetailsCache[item.id] = offline
                return offline
            }
            #endif
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("BiteFM/5.0.23 (iPad; iOS 26.3; Scale/2.00)", forHTTPHeaderField: "User-Agent")
        
        if let username = UserDefaults.standard.string(forKey: "savedUsername"),
           let password = KeychainHelper.readPassword(account: username) {
            let authString = "\(username):\(password)"
            if let authData = authString.data(using: .utf8) {
                let base64Auth = authData.base64EncodedString()
                request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
            }
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200...299).contains(status) else {
                let preview = String(data: data.prefix(400), encoding: .utf8) ?? ""
                LogManager.shared.log(
                    "Broadcast detail HTTP \(status) for \(url.absoluteString) preview=\(preview.prefix(200))",
                    type: .error
                )
                #if os(iOS)
                if let offline = offlineBroadcastDetailFromStore(terminID: item.terminID) {
                    broadcastDetailsCache[item.id] = offline
                    return offline
                }
                #endif
                return nil
            }
            // Decode off the MainActor so große JSON-Antworten die UI nicht blockieren.
            let detail = try await Task.detached(priority: .userInitiated) {
                try JSONDecoder().decode(BroadcastDetail.self, from: data)
            }.value
            broadcastDetailsCache[item.id] = detail
            return detail
        } catch {
            LogManager.shared.log("Failed to fetch/decode broadcast detail for \(url.absoluteString): \(error)", type: .error)
            #if os(iOS)
            if let offline = offlineBroadcastDetailFromStore(terminID: item.terminID) {
                broadcastDetailsCache[item.id] = offline
                return offline
            }
            #endif
            return nil
        }
    }

    #if os(iOS)
    private func offlineBroadcastDetailFromStore(terminID: Int) -> BroadcastDetail? {
        guard let container = modelContainer else { return nil }
        let ctx = ModelContext(container)
        let fd = FetchDescriptor<StoredOfflineBroadcastDetail>(
            predicate: #Predicate<StoredOfflineBroadcastDetail> { $0.terminID == terminID }
        )
        guard let row = try? ctx.fetch(fd).first else { return nil }
        return try? row.decodeDetail()
    }
    #endif
    
    /// `GET /api/v1/broadcasts/{sendung_slug}/{datum_de}/{termin_slug}/?listen=no` — erster Pfadsegment = Slug der **Sendung** (wie in der Sendungsliste), nicht immer gleich `sendung_slug` aus dem Archiv-JSON.
    private func makeBroadcastDetailURL(for item: ArchiveItem) -> URL? {
        let dateSegment = item.datumDe.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dateSegment.isEmpty else { return nil }
        let showSegment = restShowSlugForBroadcastDetailAPI(for: item)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.byte.fm"
        components.path = "/api/v1/broadcasts/\(showSegment)/\(dateSegment)/\(item.terminSlugForBroadcastAPI)/"
        components.queryItems = [URLQueryItem(name: "listen", value: "no")]
        return components.url
    }
    
    /// Slug der Sendung für die REST-URL: über `id_sendung` oder Titelabgleich mit der geladenen Sendungsliste, sonst `sendung_slug` aus dem Archiv.
    private func restShowSlugForBroadcastDetailAPI(for item: ArchiveItem) -> String {
        if let sid = item.sendungID,
           let show = shows.first(where: { $0.id == sid }) {
            return show.slug
        }
        let title = item.sendungTitel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty,
           let show = shows.first(where: { $0.titel.caseInsensitiveCompare(title) == .orderedSame }) {
            return show.slug
        }
        return item.sendungSlug
    }
}
