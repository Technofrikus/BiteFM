import Foundation
import SwiftData

/// Shared app bootstrap: SwiftData container path and service wiring for macOS and iOS targets.
@MainActor
public enum BiteFMBootstrap {
    public static func createModelContainer() throws -> ModelContainer {
        let schema = Schema([
            StoredArchiveItem.self,
            StoredFavoriteBroadcast.self,
            StoredFavoriteShow.self,
            StoredListeningHistoryEntry.self,
            StoredShow.self,
            StoredPlaybackPosition.self
        ])

        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw BootstrapError.missingApplicationSupport
        }
        let appDirectory = appSupportURL.appendingPathComponent("BiteFM")

        if !fileManager.fileExists(atPath: appDirectory.path) {
            try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }

        let storeURL = appDirectory.appendingPathComponent("BiteFM.store")
        let config = ModelConfiguration(url: storeURL)
        return try ModelContainer(for: schema, configurations: [config])
    }

    public static func configureServices(modelContainer container: ModelContainer) {
        APIClient.shared.setup(modelContainer: container)
        AudioPlayerManager.shared.setup(modelContainer: container)
    }

    public enum BootstrapError: Error {
        case missingApplicationSupport
    }
}
