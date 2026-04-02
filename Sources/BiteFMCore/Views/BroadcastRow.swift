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
                compactLayout
            } else {
                regularLayout
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isPlaying ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }

    private var regularLayout: some View {
        HStack(spacing: 0) {
            playbackBlock
            Divider()
                .frame(height: 30)
                .padding(.horizontal, 4)
            detailAffordance
        }
    }

    /// iPhone: vertical stack, full-width tap for play, explicit details button.
    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            playbackBlock
            HStack {
                Spacer(minLength: 0)
                compactDetailButton
            }
        }
    }

    private var playbackBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                heartControl
                if !isPlaying && apiClient.isPlayed(item: item) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.caption2)
                }
                Text(showShowTitle ? item.sendungTitel : item.subtitle)
                    .font(.headline)
                    .foregroundColor(isPlaying ? .accentColor : .primary)
                    .multilineTextAlignment(.leading)
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
            if isInspectorPresented {
                selectedItemForDetail = item
            }
        }
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
                #if os(macOS)
                .help(isFav ? "Favorit entfernen" : "Als Favorit speichern")
                #endif
            } else if isFav {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }

    private var detailAffordance: some View {
        HStack(spacing: 0) {
            Image(systemName: "info.circle")
                .font(.system(size: 18))
                .foregroundColor(selectedItemForDetail?.id == item.id && isInspectorPresented ? .white : .accentColor)
                .frame(width: 44, height: 44)
                .background(selectedItemForDetail?.id == item.id && isInspectorPresented ? Color.accentColor : Color.clear)
                .clipShape(Circle())
        }
        .frame(maxWidth: 60, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggleDetailPresentation)
    }

    private var compactDetailButton: some View {
        Button(action: toggleDetailPresentation) {
            Label(
                selectedItemForDetail?.id == item.id && isInspectorPresented ? "Details schließen" : "Details",
                systemImage: "info.circle"
            )
            .font(.subheadline)
            .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
    }

    private func toggleDetailPresentation() {
        if isInspectorPresented, selectedItemForDetail?.id == item.id {
            isInspectorPresented = false
        } else {
            selectedItemForDetail = item
            isInspectorPresented = true
        }
    }
}
