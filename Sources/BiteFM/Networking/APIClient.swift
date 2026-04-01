import Foundation
import os
import SwiftData

@MainActor
class APIClient: ObservableObject {
    static let shared = APIClient()
    
    @Published var isLoggedIn = false
    @Published var archiveItems: [ArchiveItem] = []
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
    @Published var showLogoutConfirmation = false
    
    var modelContainer: ModelContainer?
    
    /// Ab wann eine neue Historie-Abfrage beim Start der Wiedergabe sinnvoll ist (letzte erfolgreiche Abfrage älter als das).
    private let listeningHistoryPlaybackStaleInterval: TimeInterval = 30 * 60
    
    private static let listeningHistoryLastSuccessKey = "listeningHistoryLastFetchSuccessAt"
    
    private var broadcastDetailsCache: [Int: BroadcastDetail] = [:]
    private var pollingTask: Task<Void, Never>?
    private var archivePollingTask: Task<Void, Never>?
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        return URLSession(configuration: config)
    }()
    
    init() {
        // Check if we have saved credentials to be "logged in" immediately
        if let username = UserDefaults.standard.string(forKey: "savedUsername"),
           let _ = KeychainHelper.readPassword(account: username) {
            self.isLoggedIn = true
        }
        // Do NOT start live metadata polling globally anymore
    }
    
    func setup(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        LogManager.shared.log("APIClient setup with ModelContainer", type: .info)
        
        // Initial load of favorites and history from disk
        Task {
            let context = modelContainer.mainContext
            
            // Load Favorites
            let favoritesDescriptor = FetchDescriptor<StoredFavoriteBroadcast>()
            if let storedFavorites = try? context.fetch(favoritesDescriptor) {
                self.favoriteSlugs = Set(storedFavorites.map { $0.sendungSlug })
                LogManager.shared.log("Loaded \(self.favoriteSlugs.count) favorite slugs from disk", type: .info)
            }
            
            let favoriteShowsDescriptor = FetchDescriptor<StoredFavoriteShow>()
            if let storedShowFavorites = try? context.fetch(favoriteShowsDescriptor) {
                self.favoriteShowIDs = Set(storedShowFavorites.map { $0.showID })
                self.favoriteShowFavoritedAt = Dictionary(uniqueKeysWithValues: storedShowFavorites.map { ($0.showID, $0.createdAt) })
                LogManager.shared.log("Loaded \(self.favoriteShowIDs.count) favorite episode IDs from disk", type: .info)
            }
            
            // Load History
            let historyDescriptor = FetchDescriptor<StoredListeningHistoryEntry>()
            if let storedHistory = try? context.fetch(historyDescriptor) {
                self.listenedShowIDs = Set(storedHistory.map { $0.showID })
                LogManager.shared.log("Loaded \(self.listenedShowIDs.count) listening history entries from disk", type: .info)
            }
            
            // Load Shows
            let showsDescriptor = FetchDescriptor<StoredShow>(sortBy: [SortDescriptor(\.titel)])
            if let storedShows = try? context.fetch(showsDescriptor) {
                self.shows = storedShows.map { $0.toShow() }
                LogManager.shared.log("Loaded \(self.shows.count) shows from disk", type: .info)
            }
            
            // If we are logged in, refresh favorites and history immediately in background
            if isLoggedIn {
                await fetchFavorites(modelContext: context)
                await fetchListeningHistory(modelContext: context)
            }
        }
        
        startArchivePolling()
        startFavoritesPolling()
        startHistoryPolling()
    }
    
    private var favoritesPollingTask: Task<Void, Never>?
    private var historyPollingTask: Task<Void, Never>?
    
    func startFavoritesPolling() {
        favoritesPollingTask?.cancel()
        favoritesPollingTask = Task {
            while !Task.isCancelled {
                if isLoggedIn {
                    let context = modelContainer?.mainContext
                    await fetchFavorites(modelContext: context)
                }
                try? await Task.sleep(nanoseconds: 60 * 60 * 1_000_000_000) // 1 hour
            }
        }
    }
    
    func startHistoryPolling() {
        historyPollingTask?.cancel()
        historyPollingTask = Task {
            while !Task.isCancelled {
                if isLoggedIn {
                    let context = modelContainer?.mainContext
                    await fetchHistory(modelContext: context)
                }
                try? await Task.sleep(nanoseconds: 3 * 60 * 60 * 1_000_000_000) // 3 hours
            }
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
        LogManager.shared.log("Syncing listening history after play: \(item.sendungTitel) (ID: \(item.terminID))", type: .info)
        
        if let context = modelContainer.map({ ModelContext($0) }) {
            await fetchListeningHistory(modelContext: context)
        } else {
            await fetchListeningHistory()
        }
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
            LogManager.shared.log("Network error in performRequest: \(error.localizedDescription)", type: .error)
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
                        
                        if let context = modelContext {
                            try await syncListeningHistoryWithDatabase(items: historyResponse.data, context: context)
                        }
                    } catch {
                        LogManager.shared.log("FAILED to decode listening history: \(error)", type: .error)
                    }
                }
            }
        } catch {
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
            LogManager.shared.log("Failed to fetch favorites: \(error.localizedDescription)", type: .error)
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
            
            self.liveMetadata = metadata
            
            // Update Now Playing if live is active
            if AudioPlayerManager.shared.isLive {
                AudioPlayerManager.shared.updateNowPlayingWithMetadata(metadata)
            }
        } catch {
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
                
                // 1. Fetch favorites and history FIRST so they are ready when we switch view
                if let container = modelContainer {
                    let context = container.mainContext
                    await fetchFavorites(modelContext: context)
                    await fetchListeningHistory(modelContext: context)
                } else {
                    await fetchFavorites()
                    await fetchListeningHistory()
                }
                
                // 2. Set isLoggedIn to true to switch the UI
                isLoggedIn = true
                
                // 3. Restart polling tasks
                startArchivePolling()
                startFavoritesPolling()
                startHistoryPolling()
                
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
        // Clear favorites and history
        favoriteSlugs.removeAll()
        favoriteShowIDs.removeAll()
        favoriteShowItems.removeAll()
        favoriteTrackItems.removeAll()
        favoriteShowFavoritedAt.removeAll()
        listenedShowIDs.removeAll()
        archiveItems.removeAll()
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
                        archiveItems = items
                        
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
            LogManager.shared.log("FAILED to fetch archive: \(error.localizedDescription)", type: .error)
            errorMessage = "Failed to fetch archive: \(error.localizedDescription)"
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
                
                if let context = modelContext {
                    try await syncShowsWithDatabase(items: decodedShows, context: context)
                }
            }
        } catch {
            LogManager.shared.log("Failed to fetch shows: \(error.localizedDescription)", type: .error)
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
            return result
        } catch {
            LogManager.shared.log("Failed to fetch broadcasts for \(showSlug): \(error)", type: .error)
            return nil
        }
    }
    
    func fetchBroadcastDetail(for item: ArchiveItem) async -> BroadcastDetail? {
        if let cached = broadcastDetailsCache[item.id] {
            return cached
        }
        
        guard let url = makeBroadcastDetailURL(for: item) else {
            LogManager.shared.log(
                "Broadcast detail: keine URL (datum_de leer?) terminID=\(item.terminID) datum_de=\(item.datumDe) sendung=\(item.sendungSlug) terminSlug=\(item.terminSlug)",
                type: .error
            )
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
                return nil
            }
            let detail = try JSONDecoder().decode(BroadcastDetail.self, from: data)
            broadcastDetailsCache[item.id] = detail
            return detail
        } catch {
            LogManager.shared.log("Failed to fetch/decode broadcast detail for \(url.absoluteString): \(error)", type: .error)
            return nil
        }
    }
    
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
