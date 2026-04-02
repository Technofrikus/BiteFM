import SwiftUI

struct LiveView: View {
    private let enablePolling: Bool
    private let showsMetadataUI: Bool
    private let showsArtwork: Bool
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedStream: StreamType = .web

    init(enablePolling: Bool = true, showsMetadataUI: Bool = true, showsArtwork: Bool = true) {
        self.enablePolling = enablePolling
        self.showsMetadataUI = showsMetadataUI
        self.showsArtwork = showsArtwork
    }

    private var artworkSide: CGFloat {
        horizontalSizeClass == .compact ? 180 : 250
    }

    var body: some View {
        ScrollView {
            VStack(spacing: horizontalSizeClass == .compact ? 16 : 24) {
                if showsMetadataUI {
                    VStack(spacing: horizontalSizeClass == .compact ? 12 : 16) {
                        if showsArtwork {
                            ZStack {
                                fallbackCoverIcon

                                if let imageURL = apiClient.liveMetadata?.artistImageURL[selectedStream.rawValue],
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
                        }

                        VStack(spacing: 6) {
                            if let currentTrack = apiClient.liveMetadata?.tracks[selectedStream.rawValue]?.first {
                                Text(currentTrack.decodedBasicHTMLEntities)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)
                            }

                            if let currentShow = apiClient.liveMetadata?.currentShowTitle[selectedStream.rawValue], !currentShow.isEmpty {
                                Text(currentShow)
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }

                            if let currentSubtitle = apiClient.liveMetadata?.currentShowSubtitle[selectedStream.rawValue], !currentSubtitle.isEmpty {
                                Text(currentSubtitle)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }

                            if let currentTime = apiClient.liveMetadata?.currentShowTime[selectedStream.rawValue], !currentTime.isEmpty {
                                Text(currentTime)
                                    .font(.caption)
                                    .foregroundColor(.secondary.opacity(0.8))
                            }
                        }
                        // Feste Mindesthöhe verhindert, dass Stream-Picker und „Stream starten“ bei „nur Musik“ nach oben springen.
                        .frame(minHeight: horizontalSizeClass == .compact ? 128 : 144, alignment: .top)
                    }
                    .padding(.top)
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
                        Text(playerManager.isLive && playerManager.isPlaying && playerManager.currentStreamType == selectedStream ? "Stream stoppen" : "Stream starten")
                    }
                    .font(.body.weight(.semibold))
                    .padding(.vertical, 12)
                    .padding(.horizontal, 32)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                if showsMetadataUI {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Zuletzt gespielt")
                            .font(.headline)
                            .padding(.horizontal)

                        let history = apiClient.liveMetadata?.tracks[selectedStream.rawValue] ?? []
                        if history.count > 1 {
                            let tail = Array(history.dropFirst())
                            VStack(spacing: 0) {
                                ForEach(Array(tail.enumerated()), id: \.offset) { index, track in
                                    HStack {
                                        Text(track.decodedBasicHTMLEntities)
                                            .font(.body)
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal)

                                    if index < tail.count - 1 {
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
            apiClient.startLiveMetadataPolling()
        }
        .onDisappear {
            guard enablePolling else { return }
            apiClient.stopLiveMetadataPolling()
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
    }
    
    private var fallbackCoverIcon: some View {
        let iconSize: CGFloat = horizontalSizeClass == .compact ? 56 : 80
        let pad: CGFloat = horizontalSizeClass == .compact ? 62 : 85
        return Image(systemName: "music.note.list")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: iconSize, height: iconSize)
            .foregroundColor(.secondary)
            .padding(pad)
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(width: artworkSide, height: artworkSide)
    }
}

#Preview {
    LiveView()
        .environmentObject(APIClient.shared)
        .environmentObject(AudioPlayerManager.shared)
}
