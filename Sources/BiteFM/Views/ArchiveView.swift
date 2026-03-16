import SwiftUI
import SwiftData

struct ArchiveView: View {
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    
    var filteredShows: [Show] {
        if searchText.isEmpty {
            return apiClient.shows
        } else {
            return apiClient.shows.filter { 
                $0.titel.localizedCaseInsensitiveContains(searchText) || 
                $0.untertitel.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            List(filteredShows) { show in
                let isPlaying = playerManager.currentItem?.sendungTitel == show.titel && playerManager.isPlaying
                
                NavigationLink(destination: BroadcastListView(show: show)) {
                    HStack {
                        VStack(alignment: .leading) {
                            HStack(spacing: 4) {
                                if apiClient.isFavorite(show: show) {
                                    Image(systemName: "heart.fill")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                                Text(show.titel)
                                    .font(.headline)
                                    .foregroundColor(isPlaying ? .accentColor : .primary)
                            }
                            if !show.untertitel.isEmpty {
                                Text(show.untertitel)
                                    .font(.subheadline)
                                    .foregroundColor(isPlaying ? .accentColor.opacity(0.8) : .secondary)
                            }
                        }
                        Spacer()
                        
                        if isPlaying {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(isPlaying ? Color.accentColor.opacity(0.1) : nil)
            }
            .navigationTitle("Archiv")
            .searchable(text: $searchText, prompt: "Sendung suchen...")
            .task {
                if apiClient.shows.isEmpty {
                    await apiClient.fetchShows(modelContext: modelContext)
                }
            }
            .refreshable {
                await apiClient.fetchShows(modelContext: modelContext)
            }
        }
    }
}

#Preview {
    ArchiveView()
        .environmentObject(APIClient.shared)
}
