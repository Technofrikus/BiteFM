import SwiftUI
import SwiftData

struct ArchiveView: View {
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
    
    var body: some View {
        List(storedItems) { storedItem in
            let item = storedItem.toArchiveItem()
            HStack(spacing: 0) {
                // Playback Area (Left)
                VStack(alignment: .leading) {
                    HStack(spacing: 4) {
                        if apiClient.isFavorite(item: item) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        if apiClient.isPlayed(item: item) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.caption2)
                        }
                        Text(item.sendungTitel)
                            .font(.headline)
                    }
                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(item.datumDe) | \(item.startTime) - \(item.endTime)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .opacity(apiClient.isPlayed(item: item) ? 0.65 : 1.0)
                .onTapGesture {
                    playerManager.play(item: item)
                }
                
                // Info Area (Right)
                HStack(spacing: 12) {
                    if playerManager.currentItem?.id == item.id && playerManager.isPlaying {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(.accentColor)
                    }
                    
                    Image(systemName: "info.circle")
                        .font(.system(size: 18))
                        .foregroundColor(selectedItemForDetail?.id == item.id && isInspectorPresented ? .white : .accentColor)
                        .frame(width: 44, height: 44) // Standard Apple touch target size
                        .background(selectedItemForDetail?.id == item.id && isInspectorPresented ? Color.accentColor : Color.clear)
                        .clipShape(Circle())
                }
                .padding(.leading, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isInspectorPresented && selectedItemForDetail?.id == item.id {
                        isInspectorPresented = false
                    } else {
                        selectedItemForDetail = item
                        isInspectorPresented = true
                    }
                }
            }
            .padding(.vertical, 4)
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
                Button(action: {
                    isInspectorPresented.toggle()
                }) {
                    Label("Details anzeigen", systemImage: "sidebar.right")
                }
                .help("Info ein-/ausblenden")
            }
        }
        .task {
            // Initial fetch or manually triggered fetch from view
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
