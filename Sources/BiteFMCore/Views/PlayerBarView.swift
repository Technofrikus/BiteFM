import SwiftUI

struct PlayerBarView: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @EnvironmentObject private var apiClient: APIClient
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private func formatTime(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60

        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    private var isCompact: Bool { horizontalSizeClass == .compact }

    var body: some View {
        if playerManager.currentItem != nil || playerManager.isLive {
            VStack(spacing: 0) {
                Divider()

                if isCompact {
                    compactBody
                } else {
                    regularBody
                }
            }
        }
    }

    @ViewBuilder
    private var metadataBlock: some View {
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
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    if playerManager.isStalled {
                        ProgressView().controlSize(.small)
                    }
                }
                Text("\(item.sendungTitel) — \(item.subtitle)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            } else {
                HStack(spacing: 8) {
                    Text(item.sendungTitel)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    if playerManager.isStalled {
                        ProgressView().controlSize(.small)
                    }
                }
                Text(item.subtitle)
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

    private var transportButtons: some View {
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
            #if os(macOS)
            .keyboardShortcut(.space, modifiers: [])
            .help(playerManager.isPlaying ? "Pause (Leertaste)" : "Abspielen (Leertaste)")
            #endif

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

    private var compactBody: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                metadataBlock
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            transportButtons

            if !playerManager.isLive && playerManager.duration > 0 {
                seekRow(compactLayout: true)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Material.bar)
    }

    private var regularBody: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    metadataBlock
                }

                Spacer(minLength: 40)

                transportButtons
            }

            if !playerManager.isLive && playerManager.duration > 0 {
                seekRow(compactLayout: false)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 16)
        .background(Material.bar)
    }

    @ViewBuilder
    private func seekRow(compactLayout: Bool) -> some View {
        if compactLayout {
            VStack(spacing: 6) {
                Slider(value: Binding(
                    get: { playerManager.currentTime },
                    set: { playerManager.seek(to: $0) }
                ), in: 0...playerManager.duration)
                .controlSize(.regular)
                HStack {
                    Text(formatTime(playerManager.currentTime))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("-" + formatTime(playerManager.duration - playerManager.currentTime))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
        } else {
            HStack(spacing: 12) {
                Text(formatTime(playerManager.currentTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 45, alignment: .trailing)

                Slider(value: Binding(
                    get: { playerManager.currentTime },
                    set: { playerManager.seek(to: $0) }
                ), in: 0...playerManager.duration)
                .controlSize(.mini)

                Text("-" + formatTime(playerManager.duration - playerManager.currentTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 45, alignment: .leading)
            }
        }
    }
}
