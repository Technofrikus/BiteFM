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
        VStack(spacing: 0) {
            // Stream Selection
            Picker("Stream", selection: $selectedStream) {
                ForEach(StreamType.allCases) { stream in
                    Text(stream.displayName).tag(stream)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            ScrollView {
                VStack(spacing: horizontalSizeClass == .compact ? 16 : 24) {
                    if showsMetadataUI {
                        // Current Song / Artist Image
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
                        }
                        .padding(.top)
                    }
                    
                    // Play Button
                    Button(action: {
                        if playerManager.isLive && playerManager.isPlaying && playerManager.currentStreamType == selectedStream {
                            playerManager.pause()
                        } else {
                            playerManager.playLive(streamType: selectedStream)
                        }
                    }) {
                        HStack {
                            Image(systemName: playerManager.isLive && playerManager.isPlaying && playerManager.currentStreamType == selectedStream ? "stop.fill" : "play.fill")
                            Text(playerManager.isLive && playerManager.isPlaying && playerManager.currentStreamType == selectedStream ? "Stream stoppen" : "Stream starten")
                        }
                        .padding()
                        .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 220)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    
                    if showsMetadataUI {
                        // History
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
        }
        .onAppear {
            guard enablePolling else { return }
            apiClient.startLiveMetadataPolling()
        }
        .onDisappear {
            guard enablePolling else { return }
            apiClient.stopLiveMetadataPolling()
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
