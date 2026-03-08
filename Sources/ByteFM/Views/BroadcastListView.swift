import SwiftUI

struct BroadcastListView: View {
    let show: Show
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @State private var broadcasts: [BroadcastSummary] = []
    @State private var isLoading = false
    @State private var currentPage = 1
    @State private var hasMorePages = true
    
    @State private var selectedItemForDetail: ArchiveItem?
    @State private var isInspectorPresented = false
    
    var body: some View {
        List {
            ForEach(broadcasts) { broadcast in
                let item = broadcast.toArchiveItem(showTitle: show.titel, showSlug: show.slug)
                BroadcastRow(
                    item: item,
                    showShowTitle: false,
                    showHeart: true,
                    selectedItemForDetail: $selectedItemForDetail,
                    isInspectorPresented: $isInspectorPresented
                )
                .onAppear {
                    if broadcast.id == broadcasts.last?.id && hasMorePages && !isLoading {
                        Task {
                            await loadMore()
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
        .navigationTitle(
            apiClient.isFavorite(show: show) ? 
            Text(Image(systemName: "heart.fill")).foregroundColor(.red) + Text(" \(show.titel)") : 
            Text(show.titel)
        )
        .inspector(isPresented: $isInspectorPresented) {
            if let item = selectedItemForDetail {
                BroadcastDetailView(item: item)
                    .inspectorColumnWidth(min: 300, ideal: 400, max: 600)
            } else {
                ContentUnavailableView("Keine Sendung ausgewählt", systemImage: "info.circle")
                    .inspectorColumnWidth(min: 300, ideal: 400, max: 600)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    isInspectorPresented.toggle()
                }) {
                    Label("Details anzeigen", systemImage: "sidebar.right")
                }
                .help("Info ein-/ausblenden")
            }
        }
        .task {
            if broadcasts.isEmpty {
                await loadMore()
            }
        }
        .refreshable {
            currentPage = 1
            broadcasts = []
            hasMorePages = true
            await loadMore()
        }
        .onChange(of: isInspectorPresented) { oldValue, newValue in
            if newValue {
                ensureMinimumWidth(900)
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
    
    private func ensureMinimumWidth(_ minWidth: CGFloat) {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow || $0.isVisible }) else { return }
            var frame = window.frame
            if frame.size.width < minWidth {
                let delta = minWidth - frame.size.width
                frame.size.width = minWidth
                frame.origin.x -= delta / 2
                window.setFrame(frame, display: true, animate: true)
            }
        }
    }
}
