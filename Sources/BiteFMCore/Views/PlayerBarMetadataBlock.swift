import SwiftUI

/// Shared “now playing” title/subtitle lines for the full player bar and the iPhone mini player.
struct PlayerBarMetadataBlock: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @EnvironmentObject private var liveMetadataStore: LiveMetadataStore
    @EnvironmentObject private var progress: PlaybackProgressStore

    var showProgressLine: Bool = false

    var body: some View {
        Group {
            if let item = playerManager.currentItem {
                let currentSong: PlaylistItem? = {
                    guard let playlist = playerManager.currentPlaylist else { return nil }
                    guard let id = playerManager.currentPlaylistItemID else { return nil }
                    return playlist.first(where: { $0.id == id })
                }()

                if let song = currentSong {
                    HStack(spacing: 8) {
                        Text("\(song.artist) — \(song.title)".bitefm_sanitizedDisplayLine)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                        if showsPlaybackActivityIndicator {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if showProgressLine {
                        PlaybackProgressLine()
                            .padding(.vertical, 2)
                    }
                    Text("\(item.sendungTitel.bitefm_sanitizedDisplayLine) — \(item.subtitle.bitefm_sanitizedDisplayLine)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                } else {
                    HStack(spacing: 8) {
                        Text(item.sendungTitel.bitefm_sanitizedDisplayLine)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                        if showsPlaybackActivityIndicator {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if showProgressLine {
                        PlaybackProgressLine()
                            .padding(.vertical, 2)
                    }
                    Text(item.subtitle.bitefm_sanitizedDisplayLine)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
            } else if playerManager.isLive, let streamType = playerManager.currentStreamType {
                let metadata = liveMetadataStore.liveMetadata
                let currentTrack = metadata?.tracks[streamType.rawValue]?.first?.decodedBasicHTMLEntities ?? streamType.displayName
                let currentShow = metadata?.currentShowTitle[streamType.rawValue] ?? "BiteFM Live Stream"

                Text(currentTrack)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if showProgressLine {
                    PlaybackProgressLine()
                        .padding(.vertical, 2)
                }
                Text(currentShow)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else {
                Text("BiteFM Live Stream")
                    .font(.headline)
                    .lineLimit(1)
                if showProgressLine {
                    PlaybackProgressLine()
                        .padding(.vertical, 2)
                }
                Text("Radio für gute Musik")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(.leading)
    }

    private var showsPlaybackActivityIndicator: Bool {
        playerManager.isStalled || playerManager.isPreparingArchivePlayback
    }
}
