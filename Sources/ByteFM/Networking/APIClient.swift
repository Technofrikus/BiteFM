import Foundation
import os
import SwiftData

@MainActor
class APIClient: ObservableObject {
    static let shared = APIClient()
    
    @Published var isLoggedIn = false
    @Published var archiveItems: [ArchiveItem] = []
    @Published var favoriteSlugs: Set<String> = []
    @Published var listenedShowIDs: Set<Int> = []
    @Published var liveMetadata: LiveMetadataResponse?
    @Published var errorMessage: String?
    
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
            let context = ModelContext(modelContainer)
            
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
                    let context = modelContainer.map { ModelContext($0) }
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
                    let context = modelContainer.map { ModelContext($0) }
                    await fetchListeningHistory(modelContext: context)
                }
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000) // 30 minutes
            }
        }
    }
    
    func isFavorite(item: ArchiveItem) -> Bool {
        let slug = item.sendungSlug.lowercased()
        let title = item.sendungTitel
        let isFav = favoriteSlugs.contains(slug) || favoriteSlugs.contains(title)
        
        // Only log a few to avoid spamming
        if isFav {
            print("Found favorite: \(title) (slug: \(slug))")
        }
        return isFav
    }
    
    func isPlayed(item: ArchiveItem) -> Bool {
        return listenedShowIDs.contains(item.terminID)
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
        // For history, we might want to keep it simple and just replace with what's on server
        let descriptor = FetchDescriptor<StoredListeningHistoryEntry>()
        let oldHistory = try context.fetch(descriptor)
        for oldEntry in oldHistory {
            context.delete(oldEntry)
        }
        
        for item in items {
            let storedEntry = StoredListeningHistoryEntry(showID: item.showID, dateString: item.date)
            context.insert(storedEntry)
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
        // Clear old favorites and add new ones (simple sync)
        let descriptor = FetchDescriptor<StoredFavoriteBroadcast>()
        let oldFavorites = try context.fetch(descriptor)
        for oldFav in oldFavorites {
            context.delete(oldFav)
        }
        
        for item in items {
            let storedItem = StoredFavoriteBroadcast(from: item)
            context.insert(storedItem)
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
                    let context = modelContainer.map { ModelContext($0) }
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
                    let context = ModelContext(container)
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
        // 1. Insert or update new items
        for item in items {
            let storedItem = StoredArchiveItem(from: item)
            context.insert(storedItem)
        }
        
        // 2. Cleanup items older than 4 weeks (based on broadcast date)
        let fourWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: Date()) ?? Date()
        
        // Use FetchDescriptor for cleanup
        let descriptor = FetchDescriptor<StoredArchiveItem>(
            predicate: #Predicate<StoredArchiveItem> { $0.broadcastDate < fourWeeksAgo }
        )
        
        let oldItems = try context.fetch(descriptor)
        for oldItem in oldItems {
            context.delete(oldItem)
        }
        
        try context.save()
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
