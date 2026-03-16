import SwiftUI
import SwiftData

struct ArchiveNew: View {
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: [
        SortDescriptor(\StoredArchiveItem.datum, order: .reverse),
        SortDescriptor(\StoredArchiveItem.startTime, order: .reverse)
    ]) 
    private var storedItems: [StoredArchiveItem]
    
    @State private var selectedItemForDetail: ArchiveItem?
    @State private var isInspectorPresented = false
    @State private var hidePlayed = false
    
    var filteredItems: [StoredArchiveItem] {
        if hidePlayed {
            return storedItems.filter { !apiClient.isPlayed(broadcastID: $0.terminID) }
        }
        return storedItems
    }
    
    var body: some View {
        ZStack {
            List(filteredItems) { storedItem in
                let item = storedItem.toArchiveItem()
                BroadcastRow(
                    item: item,
                    selectedItemForDetail: $selectedItemForDetail,
                    isInspectorPresented: $isInspectorPresented
                )
            }
            .opacity(filteredItems.isEmpty ? 0 : 1)
            
            if filteredItems.isEmpty && !storedItems.isEmpty {
                ContentUnavailableView(
                    "Alle Sendungen gehört",
                    systemImage: "checkmark.circle",
                    description: Text("Du hast alle aktuellen Sendungen in dieser Liste bereits gehört.")
                )
            }
        }
        .broadcastInspector(isPresented: $isInspectorPresented, selectedItem: $selectedItemForDetail)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Button(action: {
                        hidePlayed.toggle()
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
            await apiClient.fetchArchive(modelContext: modelContext)
        }
    }
}
