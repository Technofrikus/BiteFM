import SwiftUI

struct LiveView: View {
    private let enablePolling: Bool
    private let showsMetadataUI: Bool
    private let showsArtwork: Bool
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var liveMetadataStore: LiveMetadataStore
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @EnvironmentObject private var nowPlayingDetail: NowPlayingDetailStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedStream: StreamType = .web

    init(enablePolling: Bool = true, showsMetadataUI: Bool = true, showsArtwork: Bool = true) {
        self.enablePolling = enablePolling
        self.showsMetadataUI = showsMetadataUI
        self.showsArtwork = showsArtwork
    }

    private var artworkSide: CGFloat {
        horizontalSizeClass == .compact ? 150 : 250
    }

    var body: some View {
        ScrollView {
            VStack(spacing: horizontalSizeClass == .compact ? 10 : 24) {
                if showsMetadataUI {
                    VStack(spacing: horizontalSizeClass == .compact ? 8 : 16) {
                        if showsArtwork {
                            currentArtwork
                        }

                        VStack(spacing: horizontalSizeClass == .compact ? 4 : 6) {
                            if let currentTrack = liveMetadataStore.liveMetadata?.tracks[selectedStream.rawValue]?.first {
                                Text(currentTrack.decodedBasicHTMLEntities)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)
                            }

                            if let currentShow = liveMetadataStore.liveMetadata?.currentShowTitle[selectedStream.rawValue], !currentShow.isEmpty {
                                Text(currentShow)
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }

                            if let currentSubtitle = liveMetadataStore.liveMetadata?.currentShowSubtitle[selectedStream.rawValue], !currentSubtitle.isEmpty {
                                Text(currentSubtitle)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }

                            if let currentTime = liveMetadataStore.liveMetadata?.currentShowTime[selectedStream.rawValue], !currentTime.isEmpty {
                                Text(currentTime)
                                    .font(.caption)
                                    .foregroundColor(.secondary.opacity(0.8))
                            }
                        }
                        // Keep compact phones stable without reserving so much space that history is pushed offscreen.
                        .frame(minHeight: horizontalSizeClass == .compact ? 84 : 144, alignment: .top)
                    }
                    .padding(.top, horizontalSizeClass == .compact ? 4 : 16)
                }

                // Stream picker directly above the play button for easy one-handed access.
                Picker("Stream", selection: $selectedStream) {
                    ForEach(StreamType.allCases) { stream in
                        Text(stream.displayName).tag(stream)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Button(action: {
                    if playerManager.isLive && playerManager.isPlaying && playerManager.currentStreamType == selectedStream {
                        playerManager.pause()
                    } else {
                        Task {
                            await playerManager.playLive(streamType: selectedStream)
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: playerManager.isLive && playerManager.isPlaying && playerManager.currentStreamType == selectedStream ? "stop.fill" : "play.fill")
                            .contentTransition(.identity)
                        Text(playerManager.isLive && playerManager.isPlaying && playerManager.currentStreamType == selectedStream ? "Stream stoppen" : "Stream starten")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .controlSize(.large)

                if showsMetadataUI {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Zuletzt gespielt")
                            .font(.headline)
                            .padding(.horizontal)

                        let history = liveMetadataStore.liveMetadata?.tracks[selectedStream.rawValue] ?? []
                        if history.count > 1 {
                            let tail = Array(history.dropFirst())
                            VStack(spacing: 0) {
                                // `id: \.self` statt Index: bei API-Polls wechselt die Reihenfolge weniger „Zellen-Identität“ als bei `id: \.offset`.
                                ForEach(tail, id: \.self) { track in
                                    HStack {
                                        Text(track.decodedBasicHTMLEntities)
                                            .font(.body)
                                        Spacer()
                                    }
                                    .padding(.vertical, horizontalSizeClass == .compact ? 6 : 8)
                                    .padding(.horizontal)

                                    if track != tail.last {
                                        Divider().padding(.leading)
                                    }
                                }
                            }
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(10)
                            .padding(.horizontal)
                        } else {
                            Text("Keine Historie verfügbar")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.bottom)
        }
        .onAppear {
            guard enablePolling else { return }
            liveMetadataStore.startPolling()
        }
        .onDisappear {
            guard enablePolling else { return }
            liveMetadataStore.stopPolling()
        }
        .alert("Wiedergabe", isPresented: .init(
            get: { playerManager.userFacingPlaybackError != nil },
            set: { if !$0 { playerManager.clearPlaybackError() } }
        )) {
            Button("OK", role: .cancel) {
                playerManager.clearPlaybackError()
            }
        } message: {
            Text(playerManager.userFacingPlaybackError ?? "")
        }
        .broadcastInspector(isPresented: nowPlayingDetail.isPresentedBinding, selectedItem: nowPlayingDetail.itemBinding)
    }
    
    private var fallbackCoverIcon: some View {
        let iconSize: CGFloat = horizontalSizeClass == .compact ? 56 : 80
        return Image(systemName: "music.note.list")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: iconSize, height: iconSize)
            .foregroundColor(.secondary)
            .frame(width: artworkSide, height: artworkSide)
    }

    @ViewBuilder
    private var currentArtwork: some View {
        if let imageURL = liveMetadataStore.liveMetadata?.artistImageURL[selectedStream.rawValue],
           !imageURL.isEmpty,
           !imageURL.lowercased().contains("blank.png"),
           let url = URL(string: imageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: artworkSide, height: artworkSide)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 5)
                case .empty, .failure:
                    fallbackCoverIcon
                @unknown default:
                    fallbackCoverIcon
                }
            }
            .frame(width: artworkSide, height: artworkSide)
        } else {
            fallbackCoverIcon
        }
    }
}

#Preview {
    LiveView()
        .environmentObject(APIClient.shared)
        .environmentObject(LiveMetadataStore.shared)
        .environmentObject(AudioPlayerManager.shared)
        .environmentObject(PlaybackProgressStore.shared)
}
