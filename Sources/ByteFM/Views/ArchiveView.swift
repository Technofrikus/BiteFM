import SwiftUI

struct ArchiveView: View {
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var playerManager: AudioPlayerManager
    
    var body: some View {
        List(apiClient.archiveItems) { item in
            HStack {
                VStack(alignment: .leading) {
                    Text(item.sendungTitel)
                        .font(.headline)
                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(item.datumDe) | \(item.startTime) - \(item.endTime)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                if playerManager.currentItem?.id == item.id && playerManager.isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                playerManager.play(item: item)
            }
            .padding(.vertical, 4)
        }
        .task {
            if apiClient.archiveItems.isEmpty {
                await apiClient.fetchArchive()
            }
        }
    }
}
