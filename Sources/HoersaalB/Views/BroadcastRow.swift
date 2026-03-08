import SwiftUI

struct BroadcastRow: View {
    let item: ArchiveItem
    var showShowTitle: Bool = true
    var showHeart: Bool = true
    
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var playerManager: AudioPlayerManager
    
    @Binding var selectedItemForDetail: ArchiveItem?
    @Binding var isInspectorPresented: Bool
    
    var isPlaying: Bool {
        playerManager.currentItem?.id == item.id && playerManager.isPlaying
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Playback Area (Left)
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    if showHeart {
                        let isFav = showShowTitle ? apiClient.isFavorite(item: item) : apiClient.isEpisodeFavorite(item: item)
                        if isFav {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                    if !isPlaying && apiClient.isPlayed(item: item) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                    }
                    Text(showShowTitle ? item.sendungTitel : item.subtitle)
                        .font(.headline)
                        .foregroundColor(isPlaying ? .accentColor : .primary)
                }
                if showShowTitle {
                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundColor(isPlaying ? .accentColor.opacity(0.8) : .secondary)
                }
                Text("\(item.datumDe) \(item.startTime.isEmpty ? "" : "| \(item.startTime) - \(item.endTime)")")
                    .font(.caption)
                    .foregroundColor(isPlaying ? .accentColor.opacity(0.7) : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(apiClient.isPlayed(item: item) && !isPlaying ? 0.65 : 1.0)
            .onTapGesture {
                playerManager.play(item: item)
            }
            
            // Info Area (Right)
            HStack(spacing: 12) {
                if isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(.accentColor)
                        .frame(width: 20)
                }
                
                Image(systemName: "info.circle")
                    .font(.system(size: 18))
                    .foregroundColor(selectedItemForDetail?.id == item.id && isInspectorPresented ? .white : .accentColor)
                    .frame(width: 44, height: 44)
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
        .padding(.horizontal, 8)
        .background(isPlaying ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
}
