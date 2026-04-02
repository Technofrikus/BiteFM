import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct BroadcastDetailView: View {
    let item: ArchiveItem
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @State private var detail: BroadcastDetail?
    @State private var isLoading = true
    /// Parsed once when `detail` loads. `htmlFragmentPlainText` uses NSAttributedString HTML parsing;
    /// evaluating it in `body` while `playerManager` updates (playlist highlight) caused AttributeGraph cycles.
    @State private var descriptionPlainText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Lade Sendungsdetails...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = detail {
                ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                // Header
                                VStack(alignment: .leading, spacing: 16) {
                                    if let imageUrlString = detail.moderatorImage, let url = URL(string: imageUrlString) {
                                        AsyncImage(url: url) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 100, height: 100)
                                                .clipShape(Circle())
                                        } placeholder: {
                                            ProgressView().frame(width: 100, height: 100)
                                        }
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(detail.broadcastTitle)
                                            .font(.title2)
                                            .fontWeight(.bold)
                                        
                                        Text(detail.showSubtitle)
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                        
                                        Text("Moderation: \(detail.moderator)")
                                            .font(.subheadline)
                                        
                                        Text("\(detail.showDate) | \(detail.showTime)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.bottom, 8)
                                
                                // Play Button
                                Button(action: {
                                    playerManager.play(item: item, playlist: detail.recordings.first?.playlist)
                                }) {
                                    HStack {
                                        Image(systemName: playerManager.currentItem?.id == item.id && playerManager.isPlaying ? "pause.fill" : "play.fill")
                                        Text(playerManager.currentItem?.id == item.id && playerManager.isPlaying ? "Pause" : "Abspielen")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.accentColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                
                                Divider()
                                
                                // Description
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Beschreibung")
                                        .font(.headline)
                                    
                                    Text(descriptionPlainText)
                                        .font(.body)
                                        .lineSpacing(2)
                                }
                                
                                Divider()

                                if let playlist = detail.recordings.first?.playlist, !playlist.isEmpty {
                                    BroadcastDetailPlaylistSection(item: item, playlist: playlist)
                                }
                            }
                            .padding()
                }
                .textSelection(.enabled)
            } else {
                Text("Details konnten nicht geladen werden.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: item.id) {
            isLoading = true
            detail = nil
            descriptionPlainText = ""
            let fetched = await apiClient.fetchBroadcastDetail(for: item)
            detail = fetched
            if let fetched {
                descriptionPlainText = fetched.showDescription.htmlFragmentPlainText
            }
            isLoading = false
        }
    }
}

// MARK: - Playlist section (isolated from detail body so `currentTime` does not rebuild description)

private struct BroadcastDetailPlaylistSection: View {
    let item: ArchiveItem
    let playlist: [PlaylistItem]

    @EnvironmentObject private var playerManager: AudioPlayerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Playlist")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(playlist) { song in
                    let isCurrentSong = currentSongFlag(song: song)

                    BroadcastPlaylistSongRow(
                        song: song,
                        isCurrentSong: isCurrentSong,
                        archiveItem: item,
                        playlist: playlist
                    )

                    if song.id != playlist.last?.id {
                        Divider().opacity(0.5)
                    }
                }
            }
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
    }

    private func currentSongFlag(song: PlaylistItem) -> Bool {
        guard playerManager.currentItem?.id == item.id else { return false }
        let currentTime = playerManager.currentTime
        let songIndex = playlist.firstIndex(where: { $0.id == song.id }) ?? 0
        let isLast = songIndex == playlist.count - 1

        if isLast {
            return currentTime >= Double(song.time)
        }
        let nextSong = playlist[songIndex + 1]
        return currentTime >= Double(song.time) && currentTime < Double(nextSong.time)
    }
}

// MARK: - Playlist row
// Textauswahl und Tap auf dieselbe Fläche schließen sich in SwiftUI aus; deshalb: eigene Play-Taste
// (klar erkennbar) + Kontextmenü auf der gesamten rechten Zeilenfläche (Zeit + Text + Freiraum nach rechts).

private struct BroadcastPlaylistSongRow: View {
    let song: PlaylistItem
    let isCurrentSong: Bool
    let archiveItem: ArchiveItem
    let playlist: [PlaylistItem]
    
    @EnvironmentObject private var playerManager: AudioPlayerManager
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: playFromSong) {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .scaleEffect(1.2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isCurrentSong ? Color.accentColor : Color.secondary)
                    .accessibilityLabel("An dieser Stelle abspielen")
            }
            .buttonStyle(.plain)
            .help("An dieser Stelle abspielen")
            .frame(width: 40, height: 40, alignment: .center)

            HStack(alignment: .top, spacing: 10) {
                Text(song.timeString)
                    .font(.caption2)
                    .foregroundColor(isCurrentSong ? .accentColor : .secondary)
                    .monospacedDigit()
                    .frame(width: 38, alignment: .leading)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.subheadline)
                        .fontWeight(isCurrentSong ? .bold : .medium)
                        .foregroundColor(isCurrentSong ? .accentColor : .primary)
                    Text(song.artist)
                        .font(.caption)
                        .foregroundColor(isCurrentSong ? .accentColor.opacity(0.8) : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    playFromSong()
                } label: {
                    Label("Von hier abspielen", systemImage: "play.circle")
                }
                Button {
                    copySongToPasteboard(artist: song.artist, title: song.title)
                } label: {
                    Label("Titel kopieren", systemImage: "doc.on.doc")
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isCurrentSong ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
    
    private func playFromSong() {
        if playerManager.currentItem?.id == archiveItem.id {
            playerManager.seek(to: Double(song.time))
        } else {
            playerManager.play(item: archiveItem, playlist: playlist, initialPosition: Double(song.time))
        }
    }

    private func copySongToPasteboard(artist: String, title: String) {
        let line = "\(artist) – \(title)"
        #if os(iOS)
        UIPasteboard.general.string = line
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line, forType: .string)
        #endif
    }
}
