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
    
    @State private var selectedItemForDetail: ArchiveItem?
    @State private var isInspectorPresented = false
    
    var filteredBroadcasts: [BroadcastSummary] {
        if hidePlayed {
            return broadcasts.filter { !apiClient.isPlayed(broadcastID: $0.id) }
        }
        return broadcasts
    }
    
    var body: some View {
        ZStack {
            List {
                ForEach(filteredBroadcasts) { broadcast in
                    let item = broadcast.toArchiveItem(showTitle: show.titel, showSlug: show.slug)
                    BroadcastRow(
                        item: item,
                        showShowTitle: false,
                        showHeart: true,
                        selectedItemForDetail: $selectedItemForDetail,
                        isInspectorPresented: $isInspectorPresented
                    )
                    .onAppear {
                        // Pagination logic: if we are near the end of the visible list, load more
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
            .opacity(filteredBroadcasts.isEmpty && !isLoading ? 0 : 1)
            
            if filteredBroadcasts.isEmpty && !isLoading {
                ContentUnavailableView(
                    hidePlayed ? "Keine ungehörten Sendungen" : "Keine Sendungen gefunden",
                    systemImage: hidePlayed ? "checkmark.circle" : "archivebox",
                    description: Text(hidePlayed ? "Alle Sendungen dieser Sendung wurden bereits gehört." : "")
                )
            }
        }
        .navigationTitle(apiClient.isFavorite(show: show) ? "❤️ \(show.titel)" : show.titel)
        .broadcastInspector(isPresented: $isInspectorPresented, selectedItem: $selectedItemForDetail)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
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
