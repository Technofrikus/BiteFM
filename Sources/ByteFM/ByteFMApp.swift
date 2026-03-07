import SwiftUI

@main
struct ByteFMApp: App {
    @StateObject private var apiClient = APIClient.shared
    @StateObject private var audioPlayerManager = AudioPlayerManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 400, idealWidth: 500, minHeight: 700, idealHeight: 900)
                .environmentObject(apiClient)
                .environmentObject(audioPlayerManager)
        }
    }
}

