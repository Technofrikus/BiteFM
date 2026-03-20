import SwiftUI

struct BroadcastListView: View {
    let show: Show
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @State private var broadcasts: [BroadcastSummary] = []
    @State private var isLoading = false
    @State private var currentPage = 1
    @State private var hasMorePages = true
    @State private var hidePlayed = false
    @State private var searchText = ""
    
    @State private var selectedItemForDetail: ArchiveItem?
    @State private var isInspectorPresented = false
    
    var filteredBroadcasts: [BroadcastSummary] {
        if hidePlayed {
            return broadcasts.filter { !apiClient.isPlayed(broadcastID: $0.id) }
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
                    ForEach(displayedBroadcasts) { broadcast in
                        let item = broadcast.toArchiveItem(showTitle: show.titel, showSlug: show.slug, sendungID: show.id)
                        BroadcastRow(
                            item: item,
                            showShowTitle: false,
                            showHeart: true,
                            onFavoriteTap: apiClient.isLoggedIn
                                ? { Task { await apiClient.toggleFavoriteEpisode(showID: item.terminID) } }
                                : nil,
                            selectedItemForDetail: $selectedItemForDetail,
                            isInspectorPresented: $isInspectorPresented
                        )
                        .onAppear {
                            // Pagination: Ende der geladenen (ungefilterten) Liste erreicht
                            if broadcast.id == filteredBroadcasts.last?.id && hasMorePages && !isLoading {
                                Task {
                                    await loadMoreUntilVisible()
                                }
                            }
                        }
                    }
                    
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding()
                    }
                }
            } else if filteredBroadcasts.isEmpty && !isLoading {
                ContentUnavailableView(
                    hidePlayed ? "Keine ungehörten Sendungen" : "Keine Sendungen gefunden",
                    systemImage: hidePlayed ? "checkmark.circle" : "archivebox",
                    description: Text(hidePlayed ? "Alle Sendungen dieser Sendung wurden bereits gehört." : "")
                )
            } else if !filteredBroadcasts.isEmpty && displayedBroadcasts.isEmpty {
                ContentUnavailableView(
                    "Keine Treffer",
                    systemImage: "magnifyingglass",
                    description: Text("Keine Ausgabe passt zur Suche.")
                )
            }
        }
        .searchable(text: $searchText, prompt: "Ausgabe suchen…")
        .navigationTitle(apiClient.isFavorite(show: show) ? "❤️ \(show.titel)" : show.titel)
        .broadcastInspector(isPresented: $isInspectorPresented, selectedItem: $selectedItemForDetail)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Button(action: {
                        Task { await apiClient.toggleFavoriteBroadcast(slug: show.slug, displayTitle: show.titel) }
                    }) {
                        Image(systemName: apiClient.isFavorite(show: show) ? "heart.fill" : "heart")
                            .foregroundColor(apiClient.isFavorite(show: show) ? .red : .primary)
                    }
                    .help(apiClient.isFavorite(show: show) ? "Sendung aus Favoriten entfernen" : "Sendung als Favorit speichern")
                    .disabled(!apiClient.isLoggedIn)
                    
                    Button(action: {
                        hidePlayed.toggle()
                        if hidePlayed {
                            Task {
                                await loadMoreUntilVisible()
                            }
                        }
                    }) {
                        Label(hidePlayed ? "Alle anzeigen" : "Gehörte ausblenden", 
                              systemImage: hidePlayed ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .help(hidePlayed ? "Alle Sendungen anzeigen" : "Gehörte Sendungen ausblenden")
                    
                    Button(action: {
                        isInspectorPresented.toggle()
                    }) {
                        Label("Details anzeigen", systemImage: "sidebar.right")
                    }
                    .help("Info ein-/ausblenden")
                }
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
        .refreshable {
            currentPage = 1
            broadcasts = []
            hasMorePages = true
            await loadMoreUntilVisible()
        }
    }
    
    /// Liste sichtbar, solange Einträge da sind oder noch nachgeladen wird.
    private var listShowsEpisodes: Bool {
        !displayedBroadcasts.isEmpty || isLoading
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
