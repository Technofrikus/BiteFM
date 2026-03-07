import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @State private var selectedStream: StreamType = .web
    
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
                VStack(spacing: 24) {
                    // Current Song / Artist Image
                    VStack(spacing: 16) {
                        if let imageURL = apiClient.liveMetadata?.artistImageURL[selectedStream.rawValue],
                           let url = URL(string: imageURL) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 250, height: 250)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(radius: 5)
                            } placeholder: {
                                ProgressView()
                                    .frame(width: 250, height: 250)
                            }
                        } else {
                            Image(systemName: "music.note.list")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 120, height: 120)
                                .padding(65)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        VStack(spacing: 6) {
                            if let currentTrack = apiClient.liveMetadata?.tracks[selectedStream.rawValue]?.first {
                                Text(currentTrack.unescapedHTML)
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
                        .frame(maxWidth: 220)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    
                    // History
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Zuletzt gespielt")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        let history = apiClient.liveMetadata?.tracks[selectedStream.rawValue] ?? []
                        if history.count > 1 {
                            VStack(spacing: 0) {
                                ForEach(history.dropFirst(), id: \.self) { track in
                                    HStack {
                                        Text(track.unescapedHTML)
                                            .font(.body)
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal)
                                    
                                    if track != history.last {
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
                .padding(.bottom)
            }
        }
    }
}

#Preview {
    LiveView()
        .environmentObject(APIClient.shared)
        .environmentObject(AudioPlayerManager.shared)
}
