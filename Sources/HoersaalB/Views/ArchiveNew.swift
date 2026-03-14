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
            // Initial fetch or manually triggered fetch from view
            LogManager.shared.log("ArchiveNew view appeared, fetching archive...", type: .info)
            await apiClient.fetchArchive(modelContext: modelContext)
        }
        .onChange(of: isInspectorPresented) { oldValue, newValue in
            if newValue {
                // Ensure window is wide enough for inspector
                // Ideal width of list (~400) + Sidebar (~200) + Inspector (400)
                ensureMinimumWidth(900)
            }
        }
    }

    private func ensureMinimumWidth(_ minWidth: CGFloat) {
        guard let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow || $0.isVisible }) else { return }
        var frame = window.frame
        if frame.size.width < minWidth {
            let delta = minWidth - frame.size.width
            frame.size.width = minWidth
            frame.origin.x -= delta / 2 // Expand from center
            window.setFrame(frame, display: true, animate: true)
        }
    }
}
