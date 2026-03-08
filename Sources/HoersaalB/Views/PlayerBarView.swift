import SwiftUI

struct PlayerBarView: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @EnvironmentObject private var apiClient: APIClient
    
    var body: some View {
        if playerManager.currentItem != nil || playerManager.isLive {
            VStack(spacing: 0) {
                Divider()
                
                HStack {
                    VStack(alignment: .leading) {
                        if let item = playerManager.currentItem {
                            let currentSong: PlaylistItem? = {
                                guard let playlist = playerManager.currentPlaylist else { return nil }
                                let currentTime = playerManager.currentTime
                                return playlist.last(where: { Double($0.time) <= currentTime + 1 })
                            }()
                            
                            if let song = currentSong {
                                HStack(spacing: 8) {
                                    Text("\(song.artist) — \(song.title)")
                                        .font(.headline)
                                        .lineLimit(1)
                                    if playerManager.isStalled {
                                        ProgressView().controlSize(.small)
                                    }
                                }
                                Text("\(item.sendungTitel) — \(item.subtitle)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            } else {
                                HStack(spacing: 8) {
                                    Text(item.sendungTitel)
                                        .font(.headline)
                                        .lineLimit(1)
                                    if playerManager.isStalled {
                                        ProgressView().controlSize(.small)
                                    }
                                }
                                Text(item.subtitle)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        } else if playerManager.isLive, let streamType = playerManager.currentStreamType {
                            let metadata = apiClient.liveMetadata
                            let currentTrack = metadata?.tracks[streamType.rawValue]?.first?.unescapedHTML ?? streamType.displayName
                            let currentShow = metadata?.currentShowTitle[streamType.rawValue] ?? "Hörsaal B Live Stream"
                            
                            Text(currentTrack)
                                .font(.headline)
                                .lineLimit(1)
                            Text(currentShow)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("Hörsaal B Live Stream")
                                .font(.headline)
                                .lineLimit(1)
                            Text("Radio für gute Musik")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 20) {
                        if playerManager.currentItem != nil {
                            Button(action: {
                                playerManager.skipPrevious()
                            }) {
                                Image(systemName: "backward.fill")
                                    .resizable()
                                    .frame(width: 18, height: 12)
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .disabled(playerManager.currentPlaylist == nil)
                        }

                        Button(action: {
                            playerManager.togglePlayPause()
                        }) {
                            let imageName: String = {
                                if playerManager.isPlaying {
                                    return playerManager.isLive ? "stop.circle.fill" : "pause.circle.fill"
                                } else {
                                    return "play.circle.fill"
                                }
                            }()
                            Image(systemName: imageName)
                                .resizable()
                                .frame(width: 32, height: 32)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)

                        if playerManager.currentItem != nil {
                            Button(action: {
                                playerManager.skipNext()
                            }) {
                                Image(systemName: "forward.fill")
                                    .resizable()
                                    .frame(width: 18, height: 12)
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .disabled(playerManager.currentPlaylist == nil)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Material.bar)
            }
        }
    }
}
