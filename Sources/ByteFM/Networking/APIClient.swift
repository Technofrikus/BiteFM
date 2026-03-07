import Foundation
import os

@MainActor
class APIClient: ObservableObject {
    static let shared = APIClient()
    
    @Published var isLoggedIn = false
    @Published var archiveItems: [ArchiveItem] = []
    @Published var liveMetadata: LiveMetadataResponse?
    @Published var errorMessage: String?
    
    private var broadcastDetailsCache: [Int: BroadcastDetail] = [:]
    private var pollingTask: Task<Void, Never>?
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        return URLSession(configuration: config)
    }()
    
    init() {
        startLiveMetadataPolling()
    }
    
    func startLiveMetadataPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                await fetchLiveMetadata()
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            }
        }
    }
    
    func stopLiveMetadataPolling() {
        pollingTask?.cancel()
        pollingTask = nil
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
                isLoggedIn = true
                errorMessage = nil
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
        // Clear cookies
        session.configuration.httpCookieStorage?.removeCookies(since: .distantPast)
    }
    
    func fetchArchive() async {
        guard let url = URL(string: "https://www.byte.fm/mobile-apps/v2/archiveSendungenNew.php") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("ByteFM/5.0.23 (iPad; iOS 26.3; Scale/2.00)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await session.data(for: request)
            let items = try JSONDecoder().decode([ArchiveItem].self, from: data)
            
            archiveItems = items
        } catch {
            errorMessage = "Failed to fetch archive: \(error.localizedDescription)"
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
