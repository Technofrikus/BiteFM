/*
  FavoriteEpisodesView.swift
  BiteFM

  Lists favorite episodes from get_favorites → shows[].
*/

import SwiftUI

struct FavoriteEpisodesView: View {
    enum SortMode: String, CaseIterable {
        case episodeDate = "Ausgabedatum"
        case favoritedAt = "Favorisiert am"
    }
    
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var sortMode: SortMode = .episodeDate
    @State private var selectedItemForDetail: ArchiveItem?
    @State private var isInspectorPresented = false
    
    private var sortedEpisodes: [FavoriteShowItem] {
        let items = apiClient.favoriteShowItems
        switch sortMode {
        case .episodeDate:
            return items.sorted { lhs, rhs in
                let ld = lhs.episodeBroadcastDateForSort
                let rd = rhs.episodeBroadcastDateForSort
                if ld != rd { return ld > rd }
                return lhs.id > rhs.id
            }
        case .favoritedAt:
            return items.sorted { lhs, rhs in
                let lf = apiClient.resolvedFavoritedAt(for: lhs)
                let rf = apiClient.resolvedFavoritedAt(for: rhs)
                if lf != rf { return lf > rf }
                return lhs.id > rhs.id
            }
        }
    }
    
    var body: some View {
        #if os(macOS)
        NavigationStack { episodesContent }
        #else
        episodesContent
        #endif
    }

    private var episodesContent: some View {
        Group {
            if apiClient.favoriteShowItems.isEmpty {
                if apiClient.lastListRefreshFailedWithoutNetwork {
                    ContentUnavailableView(
                        "Keine Verbindung",
                        systemImage: "wifi.slash",
                        description: Text("Du bist offline oder das Netzwerk ist nicht erreichbar. Favoriten können jetzt nicht geladen werden.")
                    )
                } else {
                    ContentUnavailableView(
                        "Keine Ausgaben-Favoriten",
                        systemImage: "heart.text.square",
                        description: Text("Favorisierte Einzel-Ausgaben erscheinen hier, sobald du welche auf byte.fm speicherst.")
                    )
                }
            } else {
                List {
                    ForEach(sortedEpisodes, id: \.id) { entry in
                        let item = entry.toArchiveItem()
                        BroadcastRow(
                            item: item,
                            showShowTitle: false,
                            showHeart: true,
                            onFavoriteTap: apiClient.isLoggedIn
                                ? { Task { await apiClient.toggleFavoriteEpisode(showID: entry.show.id) } }
                                : nil,
                            selectedItemForDetail: $selectedItemForDetail,
                            isInspectorPresented: $isInspectorPresented
                        )
                    }
                }
            }
        }
        .navigationTitle("Favoriten: Ausgaben")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                if horizontalSizeClass == .compact {
                    Menu {
                        Picker("Sortierung", selection: $sortMode) {
                            ForEach(SortMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                    } label: {
                        Label("Sortierung: \(sortMode.rawValue)", systemImage: "arrow.up.arrow.down.circle")
                    }
                } else {
                    Picker("Sortierung", selection: $sortMode) {
                        ForEach(SortMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 420)
                }
            }
            #if os(macOS)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Label("Details anzeigen", systemImage: "sidebar.right")
                }
                .help("Info ein-/ausblenden")
            }
            #endif
        }
        .broadcastInspector(isPresented: $isInspectorPresented, selectedItem: $selectedItemForDetail)
        .refreshable {
            guard !isInspectorPresented else { return }
            if let ctx = apiClient.modelContainer?.mainContext {
                await apiClient.fetchFavorites(modelContext: ctx)
            } else {
                await apiClient.fetchFavorites()
            }
        }
    }
}

#Preview {
    NavigationStack {
        FavoriteEpisodesView()
            .environmentObject(APIClient.shared)
            .environmentObject(AudioPlayerManager.shared)
    }
}
