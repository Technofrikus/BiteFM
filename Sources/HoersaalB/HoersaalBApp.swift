import SwiftUI
import SwiftData

@main
struct HoersaalBApp: App {
    @StateObject private var apiClient = APIClient.shared
    @StateObject private var audioPlayerManager = AudioPlayerManager.shared
    
    let container: ModelContainer
    
    init() {
        do {
            container = try ModelContainer(for: StoredArchiveItem.self, StoredFavoriteBroadcast.self, StoredListeningHistoryEntry.self, StoredShow.self)
            // Setup APIClient with container
            APIClient.shared.setup(modelContainer: container)
        } catch {
            fatalError("Could not initialize ModelContainer")
        }
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
        }
    }
}

