import SwiftUI

/// Shared “now playing” title/subtitle lines for the full player bar and the iPhone mini player.
struct PlayerBarMetadataBlock: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @EnvironmentObject private var apiClient: APIClient

    var body: some View {
        Group {
            if let item = playerManager.currentItem {
                let currentSong: PlaylistItem? = {
                    guard let playlist = playerManager.currentPlaylist else { return nil }
                    let currentTime = playerManager.currentTime
                    return playlist.last(where: { Double($0.time) <= currentTime + 1 })
                }()

                if let song = currentSong {
                    HStack(spacing: 8) {
                        Text("\(song.artist) — \(song.title)".bitefm_sanitizedDisplayLine)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                        if playerManager.isStalled {
                            ProgressView().controlSize(.small)
                        }
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
                        if playerManager.isStalled {
                            ProgressView().controlSize(.small)
                        }
                    }
                    Text(item.subtitle.bitefm_sanitizedDisplayLine)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
            } else if playerManager.isLive, let streamType = playerManager.currentStreamType {
                let metadata = apiClient.liveMetadata
                let currentTrack = metadata?.tracks[streamType.rawValue]?.first?.decodedBasicHTMLEntities ?? streamType.displayName
                let currentShow = metadata?.currentShowTitle[streamType.rawValue] ?? "BiteFM Live Stream"

                Text(currentTrack)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(currentShow)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else {
                Text("BiteFM Live Stream")
                    .font(.headline)
                    .lineLimit(1)
                Text("Radio für gute Musik")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(.leading)
    }
}
