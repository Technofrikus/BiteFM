import SwiftUI

struct BroadcastListView: View {
    let show: Show
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var activePlayback: ActivePlaybackStore
    @EnvironmentObject private var favoritePlayedStore: FavoritePlayedStore
    #if os(iOS)
    @EnvironmentObject private var downloadManager: IOSDownloadManager
    #endif
    @State private var broadcasts: [BroadcastSummary] = []
    @State private var isLoading = false
    @State private var currentPage = 1
    @State private var hasMorePages = true
    @State private var hidePlayed = false
    @State private var searchText = ""
    /// Narrow snapshot of the favorite/played state `BroadcastRow` needs, sourced from
    /// the shared `FavoritePlayedStore` (no per-view `@State` or `.onChange` duplication).
    @State private var selectedItemForDetail: ArchiveItem?
    @State private var isInspectorPresented = false
    
    var filteredBroadcasts: [BroadcastSummary] {
        if hidePlayed {
            let pinnedTerminID: Int? = activePlayback.isActivePlaying ? nil : activePlayback.activeTerminID
            return broadcasts.filter { broadcast in
                !favoritePlayedStore.state.listenedShowIDs.contains(broadcast.id) || broadcast.id == pinnedTerminID
            }
        }
        return broadcasts
    }
    
    /// Ausgaben der geladenen Seiten, optional nach Suchtext (wie Sendungssuche im Archiv).
    private var displayedBroadcasts: [BroadcastSummary] {
        let base = filteredBroadcasts
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return base }
        return base.filter { broadcast in
            let fields: [String] = [
                broadcast.subtitle,
                broadcast.date,
                broadcast.slug,
                broadcast.description ?? "",
                broadcast.moderator ?? ""
            ]
            return fields.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }
    
    var body: some View {
        ZStack {
            if listShowsEpisodes {
                List {
                    ForEach(Array(displayedBroadcasts.enumerated()), id: \.element.id) { idx, broadcast in
                        broadcastRow(idx: idx, broadcast: broadcast)
                    }
                    
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding()
                        .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 12, trailing: 12))
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
            } else if filteredBroadcasts.isEmpty && !isLoading {
                if apiClient.lastListRefreshFailedWithoutNetwork {
                    ContentUnavailableView(
                        "Keine Verbindung",
                        systemImage: "wifi.slash",
                        description: Text("Du bist offline oder das Netzwerk ist nicht erreichbar. Ausgaben dieser Sendung können jetzt nicht geladen werden.")
                    )
                } else {
                    if hidePlayed {
                        ContentUnavailableView {
                            Label("Keine ungehörten Sendungen", systemImage: "checkmark.circle")
                        } description: {
                            Text("Alle Sendungen dieser Sendung wurden bereits gehört.")
                        } actions: {
                            Button("Gehörte einblenden") {
                                hidePlayed = false
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        ContentUnavailableView(
                            "Keine Sendungen gefunden",
                            systemImage: "archivebox"
                        )
                    }
                }
            } else if !filteredBroadcasts.isEmpty && displayedBroadcasts.isEmpty {
                ContentUnavailableView {
                    Label("Keine Treffer", systemImage: "magnifyingglass")
                } description: {
                    Text("Keine Ausgabe passt zur Suche.")
                } actions: {
                    Button("Suche löschen") {
                        searchText = ""
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Ausgabe suchen…")
        .navigationTitle(apiClient.isFavorite(show: show) ? "❤️ \(show.titel)" : show.titel)
        .broadcastInspector(isPresented: $isInspectorPresented, selectedItem: $selectedItemForDetail)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: {
                        Task { await apiClient.toggleFavoriteBroadcast(slug: show.slug, displayTitle: show.titel) }
                    }) {
                        Label(
                            apiClient.isFavorite(show: show) ? "Sendung aus Favoriten entfernen" : "Sendung als Favorit speichern",
                            systemImage: apiClient.isFavorite(show: show) ? "heart.slash" : "heart"
                        )
                    }
                    .disabled(!apiClient.isLoggedIn)

                    Button(action: {
                        hidePlayed.toggle()
                        if hidePlayed {
                            Task { await loadMoreUntilVisible() }
                        }
                    }) {
                        Label(
                            hidePlayed ? "Gehörte einblenden" : "Gehörte ausblenden",
                            systemImage: hidePlayed ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
                        )
                    }

                    #if os(macOS)
                    Button(action: { isInspectorPresented.toggle() }) {
                        Label(isInspectorPresented ? "Details ausblenden" : "Details anzeigen", systemImage: "sidebar.right")
                    }
                    #endif
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("Optionen")
            }
        }
        .task {
            if broadcasts.isEmpty {
                await loadMoreUntilVisible()
            }
        }
        .onChange(of: show.id) { oldValue, newValue in
            Task {
                searchText = ""
                currentPage = 1
                broadcasts = []
                hasMorePages = true
                await loadMoreUntilVisible()
            }
        }
    }
    
    /// Liste sichtbar, solange Einträge da sind oder noch nachgeladen wird.
    private var listShowsEpisodes: Bool {
        !displayedBroadcasts.isEmpty || isLoading
    }
    
    @ViewBuilder
    private func broadcastRow(idx: Int, broadcast: BroadcastSummary) -> some View {
        let isFirst = idx == 0
        let isLastEpisodeRow = idx == displayedBroadcasts.count - 1
        let top: CGFloat = isFirst ? 12 : 4
        let bottom: CGFloat = isLastEpisodeRow && !isLoading ? 12 : 4
        let item = broadcast.toArchiveItem(showTitle: show.titel, showSlug: show.slug, sendungID: show.id)
        makeBroadcastRow(
            item: item,
            showShowTitle: false,
            showHeart: true,
            onFavoriteTap: apiClient.isLoggedIn
                ? { Task { await apiClient.toggleFavoriteEpisode(showID: item.terminID) } }
                : nil,
            favoritePlayed: favoritePlayedStore.state,
            selectedItemForDetail: $selectedItemForDetail,
            isInspectorPresented: $isInspectorPresented
        )
        .listRowInsets(EdgeInsets(top: top, leading: 10, bottom: bottom, trailing: 12))
        .onAppear {
            // Pagination: Ende der geladenen (ungefilterten) Liste erreicht
            if broadcast.id == filteredBroadcasts.last?.id && hasMorePages && !isLoading {
                Task {
                    await loadMoreUntilVisible()
                }
            }
        }
    }

    private func loadMoreUntilVisible() async {
        // Load initial or more items until we have enough to show or no more pages exist
        while hasMorePages && !isLoading {
            await loadMore()
            
            // If we are filtering and didn't gain enough visible items, keep loading
            if hidePlayed && filteredBroadcasts.count < 10 && hasMorePages {
                // Keep going
                continue
            } else {
                break
            }
        }
    }
    
    private func loadMore() async {
        guard !isLoading && hasMorePages else { return }
        
        isLoading = true
        if let paginated = await apiClient.fetchBroadcasts(showSlug: show.slug, page: currentPage) {
            broadcasts.append(contentsOf: paginated.results)
            currentPage += 1
            hasMorePages = currentPage <= paginated.pageCount
        } else {
            hasMorePages = false
        }
        isLoading = false
    }
}
