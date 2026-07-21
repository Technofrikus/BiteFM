import Foundation
import SwiftUI

/// Deep module that owns the live-metadata polling lifecycle and publishes the
/// narrow `LiveMetadataResponse` value that `LiveView`, `PlayerBarMetadataBlock`,
/// and `NowPlayingChrome` need.
///
/// Previously live metadata lived on the shared `APIClient` as a plain `@Published`
/// property, so its 60s poll tick triggered re-renders in **every** view observing
/// the client, not just the two that consume live metadata. List views added
/// defensive guards (equality checks, store adapters) to suppress the noise.
///
/// This store owns the polling task and offers a narrow `@Published` surface.
/// Consumers opt in by observing this store instead of the whole `APIClient`.
@MainActor
public final class LiveMetadataStore: ObservableObject {
    public static let shared = LiveMetadataStore()

    /// The raw live-metadata response. `nil` until the first successful poll.
    @Published public private(set) var liveMetadata: LiveMetadataResponse?

    private var pollingTask: Task<Void, Never>?

    private init() {}

    deinit {
        pollingTask?.cancel()
    }

    // MARK: - Polling lifecycle

    /// Starts the 60s poll loop. Safe to call multiple times — cancels any
    /// previous loop first.
    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetch()
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        }
    }

    /// Stops the poll loop and releases the task.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Fetch

    private func fetch() async {
        guard let url = URL(string: "https://www.byte.fm/api/v1/song-history/") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("BiteFM/5.0.23 (iPad; iOS 26.3; Scale/2.00)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let metadata = try JSONDecoder().decode(LiveMetadataResponse.self, from: data)
            // Same content: no @Published fire → fewer attribute invalidations.
            guard metadata != liveMetadata else { return }
            liveMetadata = metadata

            // Update Now Playing if live is active
            if AudioPlayerManager.shared.isLive {
                AudioPlayerManager.shared.updateNowPlayingWithMetadata(metadata)
            }
        } catch {
            if isBenignCancellation(error) {
                LogManager.shared.log("Live metadata fetch cancelled", type: .debug)
                return
            }
            LogManager.shared.log("Failed to fetch live metadata: \(error)", type: .error)
        }
    }

    private func isBenignCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }
}