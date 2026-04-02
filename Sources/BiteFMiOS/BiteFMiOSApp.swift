import SwiftUI
import SwiftData
import BiteFMCore

@main
struct BiteFMiOSApp: App {
    let container: ModelContainer

    init() {
        do {
            let container = try BiteFMBootstrap.createModelContainer()
            BiteFMBootstrap.configureServices(modelContainer: container)
            self.container = container
            LogManager.shared.log("ModelContainer initialized (iOS)", type: .info)
        } catch {
            LogManager.shared.log("CRITICAL ERROR: Could not initialize ModelContainer: \(error)", type: .error)
            fatalError("Could not initialize ModelContainer")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(APIClient.shared)
                .environmentObject(AudioPlayerManager.shared)
        }
        .modelContainer(container)
    }
}
