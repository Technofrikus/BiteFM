import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - iPhone mini bar

/// `.tabAccessory`: use with `tabViewBottomAccessory` — system supplies Liquid Glass / tab-bar-matched chrome (iOS 18+).
/// `.safeAreaInsetRow`: use with `safeAreaInset` fallback — own divider + bar material.
enum MiniPlayerBarChrome {
    case tabAccessory
    case safeAreaInsetRow
}

struct MiniPlayerBarView: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    /// Prefer labeling at call sites: `MiniPlayerBarView(chrome: .tabAccessory, onExpand: { … })` (avoids trailing-closure ambiguity with `chrome:`).
    var onExpand: () -> Void
    var chrome: MiniPlayerBarChrome = .safeAreaInsetRow

    var body: some View {
        switch chrome {
        case .tabAccessory:
            miniRow
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        case .safeAreaInsetRow:
            VStack(spacing: 0) {
                Divider()
                miniRow
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Material.bar)
            }
        }
    }

    private var miniRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onExpand) {
                VStack(alignment: .leading, spacing: 4) {
                    PlayerBarMetadataBlock()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { playerManager.togglePlayPause() }) {
                let imageName: String = {
                    if playerManager.isPlaying {
                        return playerManager.isLive ? "stop.circle.fill" : "pause.circle.fill"
                    }
                    return "play.circle.fill"
                }()
                Image(systemName: imageName)
                    .font(.system(size: 34))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playerManager.isPlaying ? "Pause" : "Abspielen")
            .frame(width: 44, height: 44)
        }
    }
}

// MARK: - Expanded sheet (full Now Playing)

struct ExpandedNowPlayingView: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @EnvironmentObject private var apiClient: APIClient
    @Environment(\.dismiss) private var dismiss

    /// Größere Steuerung im Sheet „Wiedergabe“ (+35 % gegenüber Player-Leiste).
    private static let expandedTransportIconScale: CGFloat = 1.35

    var body: some View {
        NavigationStack {
            Group {
                if playerManager.currentItem != nil {
                    expandedArchiveBody
                } else if playerManager.isLive {
                    expandedLiveBody
                } else {
                    ContentUnavailableView(
                        "Nichts in Wiedergabe",
                        systemImage: "music.note",
                        description: Text("Starten Sie eine Sendung oder einen Livestream.")
                    )
                }
            }
            .navigationTitle("Wiedergabe")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .onChange(of: playerManager.currentItem?.id) { _, _ in
            dismissIfNothingToShow()
        }
        .onChange(of: playerManager.isLive) { _, _ in
            dismissIfNothingToShow()
        }
    }

    private func dismissIfNothingToShow() {
        if playerManager.currentItem == nil && !playerManager.isLive {
            dismiss()
        }
    }

    @ViewBuilder
    private var expandedArchiveBody: some View {
        if let item = playerManager.currentItem {
            BroadcastDetailView(item: item, showsPrimaryPlayAction: false)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    expandedControlsChrome(live: false)
                }
        }
    }

    private var expandedLiveBody: some View {
        ExpandedLiveNowPlayingContent()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                expandedControlsChrome(live: true)
            }
    }

    /// Live: undurchsichtiger Hintergrund bis in die untere Safe Area — vermeidet den schmalen grauen Rand um die Blur-Leiste bei nur einem Stop-Button.
    private func expandedControlsChrome(live: Bool) -> some View {
        PlaybackControlsStack(
            compactTimeline: true,
            keyboardShortcut: false,
            spacing: 10,
            transportIconScale: Self.expandedTransportIconScale
        )
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background { expandedBottomBarBackground(live: live) }
    }

    @ViewBuilder
    private func expandedBottomBarBackground(live: Bool) -> some View {
#if os(iOS)
        Group {
            if live {
                Rectangle()
                    .fill(Color(uiColor: .systemBackground))
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
        }
        .ignoresSafeArea(edges: .bottom)
#else
        Rectangle()
            .fill(Material.bar)
#endif
    }
}

// MARK: - Live metadata (no ArchiveItem)

private struct ExpandedLiveNowPlayingContent: View {
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var artworkSide: CGFloat { horizontalSizeClass == .compact ? 200 : 260 }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    fallbackCoverIcon

                    if let streamType = playerManager.currentStreamType,
                       let imageURL = apiClient.liveMetadata?.artistImageURL[streamType.rawValue],
                       !imageURL.isEmpty,
                       !imageURL.lowercased().contains("blank.png"),
                       let url = URL(string: imageURL) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: artworkSide, height: artworkSide)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(radius: 5)
                            }
                        }
                        .frame(width: artworkSide, height: artworkSide)
                    }
                }

                VStack(spacing: 8) {
                    if let streamType = playerManager.currentStreamType,
                       let currentTrack = apiClient.liveMetadata?.tracks[streamType.rawValue]?.first {
                        Text(currentTrack.decodedBasicHTMLEntities)
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                    }

                    if let streamType = playerManager.currentStreamType,
                       let currentShow = apiClient.liveMetadata?.currentShowTitle[streamType.rawValue],
                       !currentShow.isEmpty {
                        Text(currentShow)
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if let streamType = playerManager.currentStreamType,
                       let currentSubtitle = apiClient.liveMetadata?.currentShowSubtitle[streamType.rawValue],
                       !currentSubtitle.isEmpty {
                        Text(currentSubtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if let streamType = playerManager.currentStreamType,
                       let currentTime = apiClient.liveMetadata?.currentShowTime[streamType.rawValue],
                       !currentTime.isEmpty {
                        Text(currentTime)
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                .padding(.horizontal)

                if let streamType = playerManager.currentStreamType {
                    Text("Stream: \(streamType.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            apiClient.startLiveMetadataPolling()
        }
    }

    private var fallbackCoverIcon: some View {
        Image(systemName: "music.note.list")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 64, height: 64)
            .foregroundColor(.secondary)
            .padding(68)
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(width: artworkSide, height: artworkSide)
    }
}
