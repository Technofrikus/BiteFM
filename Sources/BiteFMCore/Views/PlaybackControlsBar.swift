import SwiftUI

enum PlaybackTimeFormatting {
    static func string(from seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

struct PlaybackTransportButtons: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    var useKeyboardShortcut: Bool = false
    /// 1.0 = Standard (z. B. Player-Leiste); >1 für „Wiedergabe“-Sheet.
    var iconScale: CGFloat = 1

    var body: some View {
        let s = iconScale
        HStack(spacing: 20 * s) {
            if playerManager.currentItem != nil {
                Button(action: { playerManager.skipPrevious() }) {
                    Image(systemName: "backward.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18 * s, height: 12 * s)
                        .foregroundColor(.accentColor)
                        .symbolRenderingMode(.monochrome)
                }
                .buttonStyle(.plain)
                .disabled(playerManager.currentPlaylist == nil)
            }

            Button(action: { playerManager.togglePlayPause() }) {
                let imageName: String = {
                    if playerManager.isPlaying {
                        return playerManager.isLive ? "stop.circle.fill" : "pause.circle.fill"
                    }
                    return "play.circle.fill"
                }()
                Image(systemName: imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32 * s, height: 32 * s)
                    .foregroundColor(.accentColor)
                    .symbolRenderingMode(.monochrome)
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .modifier(SpaceBarPlayShortcut(enabled: useKeyboardShortcut))
            .help(playerManager.isPlaying ? "Pause (Leertaste)" : "Abspielen (Leertaste)")
            #endif

            if playerManager.currentItem != nil {
                Button(action: { playerManager.skipNext() }) {
                    Image(systemName: "forward.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18 * s, height: 12 * s)
                        .foregroundColor(.accentColor)
                        .symbolRenderingMode(.monochrome)
                }
                .buttonStyle(.plain)
                .disabled(playerManager.currentPlaylist == nil)
            }
        }
    }
}

struct PlaybackSeekBar: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    var compactTimeline: Bool

    var body: some View {
        if !playerManager.isLive && playerManager.duration > 0 {
            Group {
                if compactTimeline {
                    VStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { playerManager.currentTime },
                                set: { playerManager.seek(to: $0) }
                            ),
                            in: 0...playerManager.duration
                        )
                        .controlSize(.regular)
                        HStack {
                            Text(PlaybackTimeFormatting.string(from: playerManager.currentTime))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("-" + PlaybackTimeFormatting.string(from: playerManager.duration - playerManager.currentTime))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        Text(PlaybackTimeFormatting.string(from: playerManager.currentTime))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 45, alignment: .trailing)

                        Slider(
                            value: Binding(
                                get: { playerManager.currentTime },
                                set: { playerManager.seek(to: $0) }
                            ),
                            in: 0...playerManager.duration
                        )
                        .controlSize(.mini)

                        Text("-" + PlaybackTimeFormatting.string(from: playerManager.duration - playerManager.currentTime))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 45, alignment: .leading)
                    }
                }
            }
        }
    }
}

/// Transport + optional seek; used by expanded Now Playing bottom bar and composed inside `PlayerBarView` on macOS.
struct PlaybackControlsStack: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    var compactTimeline: Bool
    var keyboardShortcut: Bool = false
    var spacing: CGFloat = 10
    var transportIconScale: CGFloat = 1

    var body: some View {
        VStack(spacing: spacing) {
            PlaybackTransportButtons(
                useKeyboardShortcut: keyboardShortcut,
                iconScale: transportIconScale
            )
            PlaybackSeekBar(compactTimeline: compactTimeline)
        }
    }
}

#if os(macOS)
private struct SpaceBarPlayShortcut: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.keyboardShortcut(.space, modifiers: [])
        } else {
            content
        }
    }
}
#endif
