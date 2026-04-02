import SwiftUI
import SwiftData
import BiteFMCore

@main
struct BiteFMMacApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif
    
    let container: ModelContainer
    
    init() {
        do {
            let created = try BiteFMBootstrap.createModelContainer()
            BiteFMBootstrap.configureServices(modelContainer: created)
            self.container = created
            let path = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("BiteFM/BiteFM.store").path
            LogManager.shared.log("ModelContainer initialized at: \(path)", type: .info)
        } catch {
            LogManager.shared.log("CRITICAL ERROR: Could not initialize ModelContainer: \(error)", type: .error)
            fatalError("Could not initialize ModelContainer")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 400, idealWidth: 500, minHeight: 700, idealHeight: 900)
                .environmentObject(APIClient.shared)
                .environmentObject(AudioPlayerManager.shared)
        }
        .modelContainer(container)
        .commands {
            // Logout under File menu as requested
            CommandGroup(after: .newItem) {
                Button("Abmelden") {
                    APIClient.shared.requestLogoutConfirmation()
                }
                .keyboardShortcut("L", modifiers: [.command, .shift])
            }
            
            // App-specific commands
            CommandGroup(after: .appInfo) {
                Button("Abmelden (App)") {
                    APIClient.shared.requestLogoutConfirmation()
                }
                
                Divider()
                
                Button("Log-Datei anzeigen") {
                    LogManager.shared.openLogFolder()
                }
            }
            
            CommandMenu("Wiedergabe") {
                Button(AudioPlayerManager.shared.isPlaying ? "Pause" : "Abspielen") {
                    AudioPlayerManager.shared.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(AudioPlayerManager.shared.currentItem == nil && !AudioPlayerManager.shared.isLive)
                
                Divider()
                
                Button("Nächster Titel") {
                    AudioPlayerManager.shared.skipNext()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .disabled(AudioPlayerManager.shared.currentPlaylist == nil)
                
                Button("Vorheriger Titel") {
                    AudioPlayerManager.shared.skipPrevious()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(AudioPlayerManager.shared.currentPlaylist == nil)
            }
        }
    }
}

