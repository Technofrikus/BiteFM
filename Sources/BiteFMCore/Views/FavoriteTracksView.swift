/*
  FavoriteTracksView.swift
  BiteFM

  Lists favorite tracks from get_favorites → tracks[].
*/

import SwiftUI

struct FavoriteTracksView: View {
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    /// Während Archiv-URL / Detail geladen wird (wie bei leerem `audioFile1` im Player).
    @State private var loadingTerminID: Int?
    @State private var loadingTimeoutTask: Task<Void, Never>?
    
    var body: some View {
        #if os(macOS)
        NavigationStack { tracksContent }
        #else
        tracksContent
        #endif
    }

    private var tracksContent: some View {
        Group {
            if apiClient.favoriteTrackItems.isEmpty {
                ContentUnavailableView(
                    "Keine Track-Favoriten",
                    systemImage: "music.note",
                    description: Text("Favorisierte Tracks erscheinen hier, sobald du welche auf byte.fm speicherst.")
                )
            } else {
                List {
                    ForEach(apiClient.favoriteTrackItems, id: \.id) { entry in
                        favoriteTrackRow(entry: entry)
                    }
                }
            }
        }
        .navigationTitle("Favoriten: Tracks")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: playerManager.currentItem?.id) { _, newID in
            guard let tid = loadingTerminID, newID == tid else { return }
            loadingTerminID = nil
            loadingTimeoutTask?.cancel()
            loadingTimeoutTask = nil
        }
        .refreshable {
            if let ctx = apiClient.modelContainer?.mainContext {
                await apiClient.fetchFavorites(modelContext: ctx)
            } else {
                await apiClient.fetchFavorites()
            }
        }
    }
    
    @ViewBuilder
    private func favoriteTrackRow(entry: FavoriteTrackItem) -> some View {
        let item = entry.toArchiveItem()
        let terminID = item?.terminID
        let isPlaying = item.map { playerManager.currentItem?.id == $0.id && playerManager.isPlaying } ?? false
        let isLoading = terminID.map { loadingTerminID == $0 } ?? false
        let highlight = isPlaying || isLoading

        if horizontalSizeClass == .compact {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Button {
                        Task { await apiClient.toggleFavoriteTrack(trackID: entry.id, cachedItem: entry) }
                    } label: {
                        Image(systemName: apiClient.isFavoriteTrackRow(id: entry.id) ? "heart.fill" : "heart")
                            .foregroundColor(apiClient.isFavoriteTrackRow(id: entry.id) ? .red : .secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .help(apiClient.isFavoriteTrackRow(id: entry.id) ? "Favorit entfernen" : "Als Favorit speichern")
                    #endif
                    .disabled(!apiClient.isLoggedIn)
                    trackStatusIcon(isLoading: isLoading, isPlaying: isPlaying)
                }
                Button {
                    playTrack(entry)
                } label: {
                    trackTextBlock(entry: entry, isPlaying: isPlaying, isLoading: isLoading)
                }
                .buttonStyle(.plain)
                .disabled(item == nil)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(highlight ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        } else {
            HStack(spacing: 0) {
                Button {
                    Task { await apiClient.toggleFavoriteTrack(trackID: entry.id, cachedItem: entry) }
                } label: {
                    Image(systemName: apiClient.isFavoriteTrackRow(id: entry.id) ? "heart.fill" : "heart")
                        .foregroundColor(apiClient.isFavoriteTrackRow(id: entry.id) ? .red : .secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .help(apiClient.isFavoriteTrackRow(id: entry.id) ? "Favorit entfernen" : "Als Favorit speichern")
                #endif
                .disabled(!apiClient.isLoggedIn)
                .padding(.trailing, 4)

                Button {
                    playTrack(entry)
                } label: {
                    trackTextBlock(entry: entry, isPlaying: isPlaying, isLoading: isLoading)
                }
                .buttonStyle(.plain)
                .disabled(item == nil)

                Divider()
                    .frame(height: 30)
                    .padding(.horizontal, 4)

                trackStatusIcon(isLoading: isLoading, isPlaying: isPlaying)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(highlight ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private func trackStatusIcon(isLoading: Bool, isPlaying: Bool) -> some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: 44, height: 44)
    }
    
    private func playTrack(_ entry: FavoriteTrackItem) {
        guard let item = entry.toArchiveItem() else { return }
        loadingTimeoutTask?.cancel()
        loadingTerminID = item.terminID
        let targetTerminID = item.terminID
        
        loadingTimeoutTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 25_000_000_000)
                if loadingTerminID == targetTerminID {
                    loadingTerminID = nil
                }
            } catch {
                // Abgebrochen (neuer Tap / Wiedergabe gestartet)
            }
        }
        
        if entry.startOffsetSeconds > 0 {
            playerManager.play(item: item, initialPosition: entry.startOffsetSeconds)
            return
        }
        Task {
            var seconds: Double = 0
            if let detail = await apiClient.fetchBroadcastDetail(for: item),
               let sec = detail.startSeconds(matchingFavoriteTrackTitle: entry.title) {
                seconds = Double(sec)
            }
            playerManager.play(item: item, initialPosition: seconds)
        }
    }
    
    @ViewBuilder
    private func trackTextBlock(entry: FavoriteTrackItem, isPlaying: Bool, isLoading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.title)
                    .font(.headline)
                    .foregroundColor(isPlaying ? .accentColor : .primary)
                if isLoading {
                    Text("lädt …")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let b = entry.broadcast {
                Text(b.title)
                    .font(.subheadline)
                    .foregroundColor(isPlaying ? .accentColor.opacity(0.85) : .secondary)
            }
            if let s = entry.show {
                Text("\(s.subtitle) · \(s.date)")
                    .font(.caption)
                    .foregroundColor(isPlaying ? .accentColor.opacity(0.75) : .secondary)
            }
            if entry.startOffsetSeconds > 0 {
                Text("Start bei \(Self.formatPlaybackOffset(entry.startOffsetSeconds))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private static func formatPlaybackOffset(_ seconds: Double) -> String {
        let t = max(0, Int(seconds.rounded()))
        let m = t / 60
        let s = t % 60
        return String(format: "%d:%02d", m, s)
    }
}

#Preview {
    NavigationStack {
        FavoriteTracksView()
            .environmentObject(APIClient.shared)
            .environmentObject(AudioPlayerManager.shared)
    }
}
