import SwiftUI

struct PlayerBarView: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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

    private var compactBody: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                PlayerBarMetadataBlock()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PlaybackControlsStack(compactTimeline: true, keyboardShortcut: false, spacing: 10)
        }
        .padding(.horizontal)
        .padding(.vertical, 14)
        .background(Material.bar)
        .overlay(alignment: .bottom) {
            PlaybackProgressLine()
        }
    }

    private var regularBody: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    PlayerBarMetadataBlock()
                }

                Spacer(minLength: 40)

                PlaybackTransportButtons(useKeyboardShortcut: true)
            }

            PlaybackSeekBar(compactTimeline: false)
        }
        .padding(.horizontal)
        .padding(.vertical, 18)
        .background(Material.bar)
        .overlay(alignment: .bottom) {
            PlaybackProgressLine()
        }
    }
}
