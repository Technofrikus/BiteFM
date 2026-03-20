import SwiftUI
import SwiftData

@main
struct BiteFMApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif
    
    @StateObject private var apiClient = APIClient.shared
    @StateObject private var audioPlayerManager = AudioPlayerManager.shared
    
    let container: ModelContainer
    
    init() {
        do {
            let schema = Schema([
                StoredArchiveItem.self,
                StoredFavoriteBroadcast.self,
                StoredListeningHistoryEntry.self,
                StoredShow.self,
                StoredPlaybackPosition.self
            ])
            
            let fileManager = FileManager.default
            let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDirectory = appSupportURL.appendingPathComponent("BiteFM")
            
            // Ensure directory exists
            if !fileManager.fileExists(atPath: appDirectory.path) {
                try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            }
            
            let storeURL = appDirectory.appendingPathComponent("BiteFM.store")
            let config = ModelConfiguration(url: storeURL)
            
            container = try ModelContainer(for: schema, configurations: [config])
            
            // Setup APIClient and AudioPlayerManager with container
            APIClient.shared.setup(modelContainer: container)
            AudioPlayerManager.shared.setup(modelContainer: container)
            
            LogManager.shared.log("ModelContainer initialized at: \(storeURL.path)", type: .info)
        } catch {
            LogManager.shared.log("CRITICAL ERROR: Could not initialize ModelContainer: \(error)", type: .error)
            fatalError("Could not initialize ModelContainer")
        }
        
        #if os(macOS)
        MacSpacePlaybackKeyMonitor.install()
        MacPlaybackGlobalHotkey.install()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 400, idealWidth: 500, minHeight: 700, idealHeight: 900)
                .environmentObject(apiClient)
                .environmentObject(audioPlayerManager)
        }
        .modelContainer(container)
        .commands {
            // Logout under File menu as requested
            CommandGroup(after: .newItem) {
                Button("Abmelden") {
                    apiClient.showLogoutConfirmation = true
                }
                .keyboardShortcut("L", modifiers: [.command, .shift])
            }
            
            // App-specific commands
            CommandGroup(after: .appInfo) {
                Button("Abmelden (App)") {
                    apiClient.showLogoutConfirmation = true
                }
                
                Divider()
                
                Button("Log-Datei anzeigen") {
                    LogManager.shared.openLogFolder()
                }
            }
            
            CommandMenu("Wiedergabe") {
                Button(audioPlayerManager.isPlaying ? "Pause" : "Abspielen") {
                    audioPlayerManager.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(audioPlayerManager.currentItem == nil && !audioPlayerManager.isLive)
                
                Divider()
                
                Button("Nächster Titel") {
                    audioPlayerManager.skipNext()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .disabled(audioPlayerManager.currentPlaylist == nil)
                
                Button("Vorheriger Titel") {
                    audioPlayerManager.skipPrevious()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(audioPlayerManager.currentPlaylist == nil)
            }
        }
    }
}

