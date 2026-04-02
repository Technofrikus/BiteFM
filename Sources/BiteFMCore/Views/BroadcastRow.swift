import SwiftUI

struct BroadcastRow: View {
    let item: ArchiveItem
    var showShowTitle: Bool = true
    var showHeart: Bool = true
    /// When set, the heart is tappable; otherwise read-only indicator.
    var onFavoriteTap: (() -> Void)? = nil

    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Binding var selectedItemForDetail: ArchiveItem?
    @Binding var isInspectorPresented: Bool

    var isPlaying: Bool {
        playerManager.currentItem?.id == item.id && playerManager.isPlaying
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        Group {
            if isCompact {
                HStack(alignment: .top, spacing: 10) {
                    playbackTapArea
                    detailInfoButton
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    playbackTapArea
                    Divider()
                        .frame(height: 28)
                        .padding(.horizontal, 6)
                    detailInfoButton
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isPlaying ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
    }

    /// Tappable column: play; if the inspector is open, keep selection in sync.
    private var playbackTapArea: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 6) {
                heartControl
                if !isPlaying && apiClient.isPlayed(item: item) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.caption2)
                        .padding(.top, 3)
                }
                Text(showShowTitle ? item.sendungTitel : item.subtitle)
                    .font(.headline)
                    .foregroundColor(isPlaying ? .accentColor : .primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showShowTitle {
                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundColor(isPlaying ? .accentColor.opacity(0.8) : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            if isInspectorPresented {
                selectedItemForDetail = item
            }
        }
    }

    private var detailInfoButton: some View {
        let isSelected = selectedItemForDetail?.id == item.id && isInspectorPresented
        return Button(action: toggleDetailPresentation) {
            Image(systemName: "info.circle")
                .font(.system(size: 18))
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                .frame(width: 40, height: 40)
                .background(isSelected ? Color.accentColor : Color.clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "Details schließen" : "Details")
    }

    @ViewBuilder
    private var heartControl: some View {
        if showHeart {
            let isFav = showShowTitle ? apiClient.isFavorite(item: item) : apiClient.isEpisodeFavorite(item: item)
            if let onFavoriteTap {
                Button(action: onFavoriteTap) {
                    Image(systemName: isFav ? "heart.fill" : "heart")
                        .foregroundColor(isFav ? .red : .secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                #if os(macOS)
                .help(isFav ? "Favorit entfernen" : "Als Favorit speichern")
                #endif
            } else if isFav {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.top, 2)
            }
        }
    }

    private func toggleDetailPresentation() {
        if isInspectorPresented, selectedItemForDetail?.id == item.id {
            selectedItemForDetail = nil
            isInspectorPresented = false
        } else {
            selectedItemForDetail = item
            isInspectorPresented = true
        }
    }
}
