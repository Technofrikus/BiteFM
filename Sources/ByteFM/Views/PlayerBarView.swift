import SwiftUI

struct PlayerBarView: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    
    var body: some View {
        if let item = playerManager.currentItem {
            VStack(spacing: 0) {
                Divider()
                
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.sendungTitel)
                            .font(.headline)
                            .lineLimit(1)
                        Text(item.subtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        playerManager.togglePlayPause()
                    }) {
                        Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Material.bar)
            }
        }
    }
}
