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
    @Published var listenedShowIDs: Set<Int> = []
    @Published var liveMetadata: LiveMetadataResponse?
    @Published var errorMessage: String?
    @Published var showLogoutConfirmation = false
    
    var modelContainer: ModelContainer?
    
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
        
        // Initial load of favorites and history from disk
        Task {
            let context = modelContainer.mainContext
            
            // Load Favorites
            let favoritesDescriptor = FetchDescriptor<StoredFavoriteBroadcast>()
            if let storedFavorites = try? context.fetch(favoritesDescriptor) {
                self.favoriteSlugs = Set(storedFavorites.map { $0.sendungSlug })
                print("Loaded \(self.favoriteSlugs.count) favorite slugs from disk")
            }
            
            // Load History
            let historyDescriptor = FetchDescriptor<StoredListeningHistoryEntry>()
            if let storedHistory = try? context.fetch(historyDescriptor) {
                self.listenedShowIDs = Set(storedHistory.map { $0.showID })
                print("Loaded \(self.listenedShowIDs.count) listening history entries from disk")
            }
            
            // Load Shows
            let showsDescriptor = FetchDescriptor<StoredShow>(sortBy: [SortDescriptor(\.titel)])
            if let storedShows = try? context.fetch(showsDescriptor) {
                self.shows = storedShows.map { $0.toShow() }
                print("Loaded \(self.shows.count) shows from disk")
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
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000) // 30 minutes
            }
        }
    }
    
    // Helper to call fetchListeningHistory with correct naming
    private func fetchHistory(modelContext: ModelContext? = nil) async {
        await fetchListeningHistory(modelContext: modelContext)
    }
    
    func isFavorite(item: ArchiveItem) -> Bool {
        let showSlug = item.sendungSlug.lowercased()
        let terminSlug = item.terminSlug.lowercased()
        let title = item.sendungTitel
        
        return isFavorite(slug: showSlug, title: title) || isFavorite(slug: terminSlug, title: "")
    }
    
    func isFavorite(show: Show) -> Bool {
        return isFavorite(slug: show.slug, title: show.titel)
    }
    
    func isFavorite(slug: String, title: String) -> Bool {
        let lSlug = slug.lowercased()
        let isFav = favoriteSlugs.contains(lSlug) || favoriteSlugs.contains(title)
        
        // Only log a few to avoid spamming
        if isFav {
            print("Found favorite: \(title) (slug: \(lSlug))")
        }
        return isFav
    }
    
    func isEpisodeFavorite(item: ArchiveItem) -> Bool {
        let lSlug = item.terminSlug.lowercased()
        return favoriteSlugs.contains(lSlug)
    }
    
    func isPlayed(item: ArchiveItem) -> Bool {
        return listenedShowIDs.contains(item.terminID)
    }
    
    func isPlayed(broadcastID: Int) -> Bool {
        return listenedShowIDs.contains(broadcastID)
    }
    
    func markAsPlayed(item: ArchiveItem) async {
        // Here we could potentially call an API to mark it as played
        // For now, we update local history and re-fetch from server to be in sync
        // if the server actually records history upon playback starting.
        print("Marking as played: \(item.sendungTitel) (ID: \(item.terminID))")
        
        if let context = modelContainer.map({ ModelContext($0) }) {
            await fetchListeningHistory(modelContext: context)
        } else {
            await fetchListeningHistory()
        }
    }
    
    func fetchListeningHistory(modelContext: ModelContext? = nil) async {
        guard let url = URL(string: "https://www.byte.fm/mobile-apps/v2/listeningHistoryEntries.php") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("ByteFM/5.0.23 (iPad; iOS 26.3; Scale/2.00)", forHTTPHeaderField: "User-Agent")
        
        // Add Basic Auth if we have credentials
        if let username = UserDefaults.standard.string(forKey: "savedUsername"),
           let password = KeychainHelper.readPassword(account: username) {
            let authString = "\(username):\(password)"
            if let authData = authString.data(using: .utf8) {
                let base64Auth = authData.base64EncodedString()
                request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
            }
        }
        
        print("Fetching listening history from \(url.absoluteString)...")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("History response status code: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    let decoder = JSONDecoder()
                    do {
                        let historyResponse = try decoder.decode(ListeningHistoryResponse.self, from: data)
                        print("Successfully decoded history: \(historyResponse.data.count) entries")
                        
                        let ids = Set(historyResponse.data.map { $0.showID })
                        self.listenedShowIDs = ids
                        
                        if let context = modelContext {
                            try await syncListeningHistoryWithDatabase(items: historyResponse.data, context: context)
                        }
                    } catch {
                        print("FAILED to decode listening history: \(error)")
                        if let jsonString = String(data: data, encoding: .utf8) {
                            print("Raw JSON response: \(jsonString)")
                        }
                    }
                }
            }
        } catch {
            print("Failed to fetch listening history: \(error.localizedDescription)")
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
        request.setValue("ByteFM/5.0.23 (iPad; iOS 26.3; Scale/2.00)", forHTTPHeaderField: "User-Agent")
        
        // Add Basic Auth if we have credentials (as per the curl provided)
        if let username = UserDefaults.standard.string(forKey: "savedUsername"),
           let password = KeychainHelper.readPassword(account: username) {
            let authString = "\(username):\(password)"
            if let authData = authString.data(using: .utf8) {
                let base64Auth = authData.base64EncodedString()
                request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
            }
        }
        
        print("Fetching favorites from \(url.absoluteString)...")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("Favorites response status code: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    let decoder = JSONDecoder()
                    
                    do {
                        let favoritesResponse = try decoder.decode(FavoritesResponse.self, from: data)
                        print("Successfully decoded FavoritesResponse. Shows: \(favoritesResponse.shows.count), Tracks: \(favoritesResponse.tracks.count), Broadcasts: \(favoritesResponse.broadcasts.count)")
                        
                        // Extract all broadcast slugs and titles from shows, tracks, and broadcasts sections
                        var slugs = Set<String>()
                        var syncItems: [FavoriteBroadcast] = []
                        
                        // Helper to add broadcast info
                        let addBroadcast = { (info: BroadcastInfo) in
                            let slug = info.slug.lowercased()
                            slugs.insert(slug)
                            slugs.insert(info.title)
                            
                            if !syncItems.contains(where: { $0.sendungSlug == slug }) {
                                syncItems.append(FavoriteBroadcast(sendungTitel: info.title, sendungSlug: slug))
                            }
                        }
                        
                        // 1. From "broadcasts" section (The primary source)
                        for item in favoritesResponse.broadcasts {
                            addBroadcast(item.broadcast)
                        }
                        
                        // 2. From "shows" section (Favorites of specific episodes also count for the broadcast)
                        for item in favoritesResponse.shows {
                            addBroadcast(item.broadcast)
                        }
                        
                        // 3. From "tracks" section
                        for item in favoritesResponse.tracks {
                            if let broadcastInfo = item.broadcast {
                                addBroadcast(broadcastInfo)
                            }
                        }
                        
                        self.favoriteSlugs = slugs
                        print("Updated favorite slugs/titles: \(self.favoriteSlugs.count) items")
                        
                        if let context = modelContext {
                            try await syncFavoritesWithDatabase(items: syncItems, context: context)
                        }
                    } catch {
                        print("FAILED to decode FavoritesResponse: \(error)")
                        if let jsonString = String(data: data, encoding: .utf8) {
                            print("Raw JSON response: \(jsonString)")
                        }
                    }
                } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    print("Unauthorized fetch favorites. Possible cookie/session issue.")
                }
            }
        } catch {
            print("Failed to fetch favorites with error: \(error.localizedDescription)")
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
        request.setValue("ByteFM/5.0.23 (iPad; iOS 26.3; Scale/2.00)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await session.data(for: request)
            let metadata = try JSONDecoder().decode(LiveMetadataResponse.self, from: data)
            
            self.liveMetadata = metadata
            
            // Update Now Playing if live is active
            if AudioPlayerManager.shared.isLive {
                AudioPlayerManager.shared.updateNowPlayingWithMetadata(metadata)
            }
        } catch {
            print("Failed to fetch live metadata: \(error)")
        }
    }
    
    func autoLogin() async {
        guard let username = UserDefaults.standard.string(forKey: "savedUsername"),
              let password = KeychainHelper.readPassword(account: username) else {
            return
        }
        await login(username: username, password: password, isAutoLogin: true)
    }
    
    func login(username: String, password: String, isAutoLogin: Bool = false) async {
        guard let url = URL(string: "https://www.byte.fm/mobile-apps/v2/verifyUsernamePassword.php") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("ByteFM/5.0.23 (iPad; iOS 26.3; Scale/2.00)", forHTTPHeaderField: "User-Agent")
        
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
            } else {
                isLoggedIn = false
                if !isAutoLogin {
                    errorMessage = "Login fehlgeschlagen"
                }
            }
        } catch {
            isLoggedIn = false
            if !isAutoLogin {
                errorMessage = error.localizedDescription
            }
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
        listenedShowIDs.removeAll()
        archiveItems.removeAll()
        
        // Clear favorites and history from database
        if let container = modelContainer {
            let context = ModelContext(container)
            if let favorites = try? context.fetch(FetchDescriptor<StoredFavoriteBroadcast>()) {
                for fav in favorites {
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
        guard let url = URL(string: "https://www.byte.fm/mobile-apps/v2/archiveSendungenNew.php") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("ByteFM/5.0.23 (iPad; iOS 26.3; Scale/2.00)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await session.data(for: request)
            let items = try JSONDecoder().decode([ArchiveItem].self, from: data)
            
            archiveItems = items
            
            if let context = modelContext {
                try await syncWithDatabase(items: items, context: context)
            }
        } catch {
            errorMessage = "Failed to fetch archive: \(error.localizedDescription)"
        }
    }

    private func syncWithDatabase(items: [ArchiveItem], context: ModelContext) async throws {
        // Use a stable update pattern to avoid SwiftData fatal errors
        let descriptor = FetchDescriptor<StoredArchiveItem>()
        let existingEntries = try context.fetch(descriptor)
        let existingMap = Dictionary(uniqueKeysWithValues: existingEntries.map { ($0.terminID, $0) })
        
        // 1. Update existing or insert new items
        for item in items {
            if let existing = existingMap[item.terminID] {
                // Update properties if needed, but for archive items they are usually static
                // Let's just update common things to ensure they're in sync
                existing.audioFile1 = item.audioFile1
                existing.audioFile2 = item.audioFile2
                existing.audioFile3 = item.audioFile3
                existing.sendungTitel = item.sendungTitel
                existing.untertitelSendung = item.untertitelSendung
                existing.terminSlug = item.terminSlug
                existing.sendungSlug = item.sendungSlug
                existing.datum = item.datum
                existing.datumDe = item.datumDe
                existing.startTime = item.startTime
                existing.endTime = item.endTime
                existing.untertitelTermin = item.untertitelTermin
            } else {
                let storedItem = StoredArchiveItem(from: item)
                context.insert(storedItem)
            }
        }
        
        // 2. Cleanup items older than 4 weeks (based on broadcast date)
        let fourWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: Date()) ?? Date()
        
        // Only cleanup older items
        let oldItems = existingEntries.filter { $0.broadcastDate < fourWeeksAgo }
        for oldItem in oldItems {
            context.delete(oldItem)
        }
        
        try context.save()
    }
    
    func fetchShows(modelContext: ModelContext? = nil) async {
        guard let url = URL(string: "https://www.byte.fm/mobile-apps/v2/archiveSendungen.php") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("ByteFM/5.0.23 (iPad; iOS 26.3; Scale/2.00)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await session.data(for: request)
            let decodedShows = try JSONDecoder().decode([Show].self, from: data)
            self.shows = decodedShows
            
            if let context = modelContext {
                try await syncShowsWithDatabase(items: decodedShows, context: context)
            }
        } catch {
            print("Failed to fetch shows: \(error.localizedDescription)")
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
        
        print("Fetching broadcasts for \(showSlug) from \(url.absoluteString)...")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("ByteFM/5.0.23 (iPad; iOS 26.3; Scale/2.00)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await session.data(for: request)
            let result = try JSONDecoder().decode(PaginatedBroadcasts.self, from: data)
            return result
        } catch {
            print("Failed to fetch broadcasts for \(showSlug): \(error)")
            return nil
        }
    }
    
    func fetchBroadcastDetail(for item: ArchiveItem) async -> BroadcastDetail? {
        if let cached = broadcastDetailsCache[item.id] {
            return cached
        }
        
        guard let url = item.detailURL else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("ByteFM/5.0.23 (iPad; iOS 26.3; Scale/2.00)", forHTTPHeaderField: "User-Agent")
        
        // Add Basic Auth if we have credentials
        if let username = UserDefaults.standard.string(forKey: "savedUsername"),
           let password = KeychainHelper.readPassword(account: username) {
            let authString = "\(username):\(password)"
            if let authData = authString.data(using: .utf8) {
                let base64Auth = authData.base64EncodedString()
                request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
            }
        }
        
        do {
            let (data, _) = try await session.data(for: request)
            let detail = try JSONDecoder().decode(BroadcastDetail.self, from: data)
            broadcastDetailsCache[item.id] = detail
            return detail
        } catch {
            print("Failed to fetch broadcast detail: \(error)")
            return nil
        }
    }
}
