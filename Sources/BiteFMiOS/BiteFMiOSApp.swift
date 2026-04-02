import SwiftUI
import SwiftData
import UIKit
import BiteFMCore

/// Relays background `URLSession` events so downloads can finish after the app was suspended.
final class BiteFMiOSAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        if identifier == IOSDownloadManager.backgroundSessionIdentifier {
            IOSDownloadManager.shared.setBackgroundCompletionHandler(completionHandler)
        } else {
            completionHandler()
        }
    }
}

@main
struct BiteFMiOSApp: App {
    @UIApplicationDelegateAdaptor(BiteFMiOSAppDelegate.self) private var appDelegate

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
                .environmentObject(IOSDownloadManager.shared)
        }
        .modelContainer(container)
    }
}
