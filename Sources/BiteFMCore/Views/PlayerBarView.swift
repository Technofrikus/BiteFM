import SwiftUI

struct PlayerBarView: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @EnvironmentObject private var nowPlayingDetail: NowPlayingDetailStore
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

                if playerManager.currentItem != nil {
                    detailInfoButton
                }

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

    /// Info button matching the list rows' `info.circle` affordance: opens the currently
    /// playing item's details in the shared inspector/sheet, wherever the user currently is.
    private var detailInfoButton: some View {
        let isSelected = nowPlayingDetail.isPresented && nowPlayingDetail.item?.id == playerManager.currentItem?.id
        return Button(action: toggleDetailPresentation) {
            Image(systemName: "info.circle")
                .font(.system(size: 18))
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                .frame(width: 28, height: 28)
                .background(isSelected ? Color.accentColor : Color.clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "Details schließen" : "Details")
        .help(isSelected ? "Details schließen" : "Details anzeigen")
    }

    private func toggleDetailPresentation() {
        guard let item = playerManager.currentItem else { return }
        if nowPlayingDetail.isPresented, nowPlayingDetail.item?.id == item.id {
            nowPlayingDetail.dismiss()
        } else {
            nowPlayingDetail.present(item)
        }
    }
}
