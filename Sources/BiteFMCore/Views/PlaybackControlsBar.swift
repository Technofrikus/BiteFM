import SwiftUI
#if os(iOS)
import AVKit
#endif

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
        #if os(iOS)
        HStack(spacing: 18 * s) {
            if playerManager.currentItem != nil {
                NowPlayingTransportButton(
                    systemName: "backward.fill",
                    iconSide: 18 * s,
                    hitSide: 44 * s
                ) { playerManager.skipPrevious() }
                .disabled(playerManager.currentPlaylist == nil)
            }

            NowPlayingTransportButton(
                systemName: playPauseSystemName,
                iconSide: 28 * s,
                hitSide: 56 * s,
                isPrimary: true
            ) { playerManager.togglePlayPause() }

            if playerManager.currentItem != nil {
                NowPlayingTransportButton(
                    systemName: "forward.fill",
                    iconSide: 18 * s,
                    hitSide: 44 * s
                ) { playerManager.skipNext() }
                .disabled(playerManager.currentPlaylist == nil)
            }
        }
        #else
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
                    .contentTransition(.identity)
            }
            .buttonStyle(.plain)
            .modifier(SpaceBarPlayShortcut(enabled: useKeyboardShortcut))
            .help(playerManager.isPlaying ? "Pause (Leertaste)" : "Abspielen (Leertaste)")

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
        #endif
    }

    private var playPauseSystemName: String {
        if playerManager.isPlaying {
            return playerManager.isLive ? "stop.fill" : "pause.fill"
        }
        return "play.fill"
    }
}

struct PlaybackSeekBar: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @EnvironmentObject private var progress: PlaybackProgressStore
    var compactTimeline: Bool

    /// Lokaler Drag-Wert, damit die 1-Hz-`currentTime`-Veröffentlichung nicht direkt in die
    /// `Slider`-Binding zurückgeschrieben wird (Echo-Schleife). Während des Ziehens steuert der
    /// lokale Wert den Slider; beim Loslassen wird einmalig geseekt.
    @State private var dragValue: Double = 0
    @State private var isEditing: Bool = false

    var body: some View {
        if !playerManager.isLive && progress.duration > 0 {
            let duration = progress.duration
            Group {
                if compactTimeline {
                    VStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { isEditing ? dragValue : progress.currentTime },
                                set: { dragValue = $0 }
                            ),
                            in: 0...duration,
                            onEditingChanged: { editing in
                                isEditing = editing
                                if editing {
                                    dragValue = progress.currentTime
                                } else {
                                    playerManager.seek(to: dragValue)
                                }
                            }
                        )
                        .controlSize(.regular)
                        HStack {
                            Text(PlaybackTimeFormatting.string(from: isEditing ? dragValue : progress.currentTime))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("-" + PlaybackTimeFormatting.string(from: max(0, duration - (isEditing ? dragValue : progress.currentTime))))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        Text(PlaybackTimeFormatting.string(from: isEditing ? dragValue : progress.currentTime))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 45, alignment: .trailing)

                        Slider(
                            value: Binding(
                                get: { isEditing ? dragValue : progress.currentTime },
                                set: { dragValue = $0 }
                            ),
                            in: 0...duration,
                            onEditingChanged: { editing in
                                isEditing = editing
                                if editing {
                                    dragValue = progress.currentTime
                                } else {
                                    playerManager.seek(to: dragValue)
                                }
                            }
                        )
                        .controlSize(.mini)

                        Text("-" + PlaybackTimeFormatting.string(from: max(0, duration - (isEditing ? dragValue : progress.currentTime))))
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
    #if os(iOS)
    /// System-Auswahl für AirPlay/Bluetooth-Audio (`AVRoutePickerView`).
    var showsAirPlayRoutePicker: Bool = false
    #endif

    var body: some View {
        VStack(spacing: spacing) {
            #if os(iOS)
            if showsAirPlayRoutePicker {
                ZStack {
                    HStack {
                        Spacer(minLength: 0)
                        PlaybackTransportButtons(
                            useKeyboardShortcut: keyboardShortcut,
                            iconScale: transportIconScale
                        )
                        Spacer(minLength: 0)
                    }
                    HStack {
                        Spacer(minLength: 0)
                        AirPlayRoutePickerRepresentable()
                            .frame(width: 36 * transportIconScale, height: 36 * transportIconScale)
                    }
                }
            } else {
                PlaybackTransportButtons(
                    useKeyboardShortcut: keyboardShortcut,
                    iconScale: transportIconScale
                )
            }
            #else
            PlaybackTransportButtons(
                useKeyboardShortcut: keyboardShortcut,
                iconScale: transportIconScale
            )
            #endif
            PlaybackSeekBar(compactTimeline: compactTimeline)
        }
    }
}

#if os(iOS)
/// Zeigt den Route-Picker von iOS (AirPlay, Lautsprecher, BT) — gleiche System-UI wie in anderen Musik-Apps.
private struct AirPlayRoutePickerRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.prioritizesVideoDevices = false
        v.tintColor = .label
        return v
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

private struct NowPlayingTransportButton: View {
    let systemName: String
    let iconSide: CGFloat
    let hitSide: CGFloat
    var isPrimary: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSide, weight: .semibold, design: .default))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isPrimary ? Color.primary : Color.secondary)
                .contentTransition(.identity)
                .frame(width: hitSide, height: hitSide)
                .contentShape(Circle())
                .background {
                    Circle()
                        .fill(.thinMaterial)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                        }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}
#endif

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
