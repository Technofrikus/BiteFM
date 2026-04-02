import SwiftUI
#if os(iOS)
import SwiftData
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct BroadcastDetailView: View {
    let item: ArchiveItem
    /// When embedded in Now Playing, the primary play banner is redundant (transport bar handles playback).
    var showsPrimaryPlayAction: Bool = true
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var playerManager: AudioPlayerManager
    #if os(iOS)
    @Environment(\.modelContext) private var modelContext
    @State private var localModeratorImageURL: URL?
    #endif
    @State private var detail: BroadcastDetail?
    @State private var isLoading = true
    /// Parsed once when `detail` loads. `htmlFragmentPlainText` uses NSAttributedString HTML parsing;
    /// evaluating it in `body` while `playerManager` updates (playlist highlight) caused AttributeGraph cycles.
    @State private var descriptionPlainText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Lade Sendungsdetails...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = detail {
                ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                // Header
                                VStack(alignment: .leading, spacing: 16) {
                                    moderatorAvatar(detail: detail)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(detail.broadcastTitle.bitefm_sanitizedDisplayLine)
                                            .font(.title2)
                                            .fontWeight(.bold)
                                        
                                        Text(detail.showSubtitle)
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                        
                                        Text("Moderation: \(detail.moderator)")
                                            .font(.subheadline)
                                        
                                        Text("\(detail.showDate) | \(detail.showTime)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.bottom, 8)

                                #if os(iOS)
                                if showsPrimaryPlayAction {
                                    HStack(alignment: .center, spacing: 14) {
                                        BroadcastDetailDownloadGlyphColumn(item: item, detail: detail)
                                            .environmentObject(playerManager)
                                        playCapsuleButton(detail: detail)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Divider()
                                } else {
                                    BroadcastDetailDownloadBar(item: item, detail: detail)
                                    Divider()
                                }
                                #else
                                if showsPrimaryPlayAction {
                                    Button(action: {
                                        if playerManager.currentItem?.id == item.id {
                                            playerManager.togglePlayPause()
                                        } else {
                                            playerManager.play(item: item, playlist: detail.recordings.first?.playlist)
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: primaryPlayIconName)
                                            Text(primaryPlayLabel)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color.accentColor)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)

                                    Divider()
                                }
                                #endif
                                
                                // Description
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Beschreibung")
                                        .font(.headline)
                                    
                                    Text(descriptionPlainText)
                                        .font(.body)
                                        .lineSpacing(2)
                                }
                                
                                Divider()

                                if let playlist = detail.recordings.first?.playlist, !playlist.isEmpty {
                                    BroadcastDetailPlaylistSection(item: item, playlist: playlist)
                                }
                            }
                            .padding()
                }
                .textSelection(.enabled)
            } else {
                Text("Details konnten nicht geladen werden.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: item.id) {
            isLoading = true
            detail = nil
            descriptionPlainText = ""
            #if os(iOS)
            localModeratorImageURL = IOSDownloadManager.resolvedModeratorImageURL(terminID: item.terminID, context: modelContext)
            #endif
            let fetched = await apiClient.fetchBroadcastDetail(for: item)
            detail = fetched
            if let fetched {
                descriptionPlainText = fetched.showDescription.htmlFragmentPlainText
            }
            #if os(iOS)
            localModeratorImageURL = IOSDownloadManager.resolvedModeratorImageURL(terminID: item.terminID, context: modelContext)
            #endif
            isLoading = false
        }
    }

    private var primaryPlayLabel: String {
        guard playerManager.currentItem?.id == item.id else { return "Abspielen" }
        return playerManager.isPlaying ? "Pause" : "Abspielen"
    }

    private var primaryPlayIconName: String {
        guard playerManager.currentItem?.id == item.id else { return "play.fill" }
        return playerManager.isPlaying ? "pause.fill" : "play.fill"
    }

    #if os(iOS)
    /// Kompakter Play-Button (analog zur Kapsel im Live-Stream), kleiner als die frühere volle Breite.
    private func playCapsuleButton(detail: BroadcastDetail) -> some View {
        Button(action: {
            if playerManager.currentItem?.id == item.id {
                playerManager.togglePlayPause()
            } else {
                playerManager.play(item: item, playlist: detail.recordings.first?.playlist)
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: primaryPlayIconName)
                Text(primaryPlayLabel)
            }
            .font(.callout.weight(.semibold))
            .padding(.vertical, 8)
            .padding(.horizontal, 22)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    #endif

    @ViewBuilder
    private func moderatorAvatar(detail: BroadcastDetail) -> some View {
        #if os(iOS)
        if let local = localModeratorImageURL,
           let uiImage = UIImage(contentsOfFile: local.path) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 100, height: 100)
                .clipShape(Circle())
        } else if let imageUrlString = detail.moderatorImage, let url = URL(string: imageUrlString) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
            } placeholder: {
                ProgressView().frame(width: 100, height: 100)
            }
        }
        #elseif os(macOS)
        if let imageUrlString = detail.moderatorImage, let url = URL(string: imageUrlString) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
            } placeholder: {
                ProgressView().frame(width: 100, height: 100)
            }
        }
        #endif
    }
}

// MARK: - iOS download bar

#if os(iOS)
/// Nur Symbol-Spalte links vom Play-Button: ohne prominente Füllung.
/// Nutzt `@Query` statt `IOSDownloadManager` als `EnvironmentObject`, damit bei laufendem Download
/// nicht die gesamte Detailansicht (inkl. Now-Playing-Sheet) bei jedem Fortschritts-Tick neu aufgebaut wird.
private struct BroadcastDetailDownloadGlyphColumn: View {
    let item: ArchiveItem
    let detail: BroadcastDetail
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Query private var storedRows: [StoredDownloadedEpisode]

    private let glyphBox: CGFloat = 40

    init(item: ArchiveItem, detail: BroadcastDetail) {
        self.item = item
        self.detail = detail
        let tid = item.terminID
        _storedRows = Query(filter: #Predicate<StoredDownloadedEpisode> { $0.terminID == tid })
    }

    var body: some View {
        let row = storedRows.first
        Group {
            if let row {
                switch row.status {
                case .downloaded:
                    Button {
                        playerManager.play(item: item)
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Lokal abspielen")
                case .downloading:
                    downloadRing(progress: row.progress)
                        .accessibilityLabel("Wird heruntergeladen")
                case .queued, .preparing:
                    ProgressView()
                        .controlSize(.regular)
                case .failed:
                    Button {
                        Task { await IOSDownloadManager.shared.startDownload(for: item, preloadedDetail: detail) }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.title2)
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Download erneut versuchen")
                }
            } else {
                Button {
                    Task { await IOSDownloadManager.shared.startDownload(for: item, preloadedDetail: detail) }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Herunterladen")
            }
        }
        .frame(width: glyphBox, height: glyphBox)
    }

    private func downloadRing(progress: Double) -> some View {
        let p = min(1, max(0, progress))
        return ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.28), lineWidth: 2.4)
            Circle()
                .trim(from: 0, to: CGFloat(p))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 28, height: 28)
    }
}

/// Zeile unter der Überschrift, wenn kein Primär-Play (z. B. Now-Playing-Sheet): erklärender Text, keine „Prominent“-Füllung.
private struct BroadcastDetailDownloadBar: View {
    let item: ArchiveItem
    let detail: BroadcastDetail
    @Query private var storedRows: [StoredDownloadedEpisode]

    init(item: ArchiveItem, detail: BroadcastDetail) {
        self.item = item
        self.detail = detail
        let tid = item.terminID
        _storedRows = Query(filter: #Predicate<StoredDownloadedEpisode> { $0.terminID == tid })
    }

    var body: some View {
        let row = storedRows.first
        HStack(spacing: 12) {
            if let row {
                switch row.status {
                case .downloaded:
                    Label("Heruntergeladen", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .downloading:
                    ProgressView(value: row.progress)
                    Text("Wird heruntergeladen …")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                case .queued, .preparing:
                    ProgressView()
                    Text("Download wird vorbereitet …")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                case .failed:
                    Button {
                        Task { await IOSDownloadManager.shared.startDownload(for: item, preloadedDetail: detail) }
                    } label: {
                        Label("Download erneut versuchen", systemImage: "arrow.clockwise.circle")
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    Task { await IOSDownloadManager.shared.startDownload(for: item, preloadedDetail: detail) }
                } label: {
                    Label("Herunterladen", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif

// MARK: - Playlist section (isolated from detail body so `currentTime` does not rebuild description)

private struct BroadcastDetailPlaylistSection: View {
    let item: ArchiveItem
    let playlist: [PlaylistItem]

    @EnvironmentObject private var playerManager: AudioPlayerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Playlist")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(playlist) { song in
                    let isCurrentSong = currentSongFlag(song: song)

                    BroadcastPlaylistSongRow(
                        song: song,
                        isCurrentSong: isCurrentSong,
                        archiveItem: item,
                        playlist: playlist
                    )

                    if song.id != playlist.last?.id {
                        Divider().opacity(0.5)
                    }
                }
            }
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func currentSongFlag(song: PlaylistItem) -> Bool {
        guard playerManager.currentItem?.id == item.id else { return false }
        let currentTime = playerManager.currentTime
        let songIndex = playlist.firstIndex(where: { $0.id == song.id }) ?? 0
        let isLast = songIndex == playlist.count - 1

        if isLast {
            return currentTime >= Double(song.time)
        }
        let nextSong = playlist[songIndex + 1]
        return currentTime >= Double(song.time) && currentTime < Double(nextSong.time)
    }
}

// MARK: - Playlist row
// Textauswahl und Tap auf dieselbe Fläche schließen sich in SwiftUI aus; deshalb: eigene Play-Taste
// (klar erkennbar) + Kontextmenü auf der gesamten rechten Zeilenfläche (Zeit + Text + Freiraum nach rechts).

private struct BroadcastPlaylistSongRow: View {
    let song: PlaylistItem
    let isCurrentSong: Bool
    let archiveItem: ArchiveItem
    let playlist: [PlaylistItem]
    
    @EnvironmentObject private var playerManager: AudioPlayerManager
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isCurrentSong {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .accessibilityHidden(true)
            }
            HStack(alignment: .top, spacing: 10) {
                Button(action: playFromSong) {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .scaleEffect(1.2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isCurrentSong ? Color.accentColor : Color.secondary)
                        .accessibilityLabel("An dieser Stelle abspielen")
                }
                .buttonStyle(.plain)
                .help("An dieser Stelle abspielen")
                .frame(width: 40, height: 40, alignment: .center)

                HStack(alignment: .top, spacing: 10) {
                    Text(song.timeString)
                        .font(.caption2)
                        .foregroundColor(isCurrentSong ? .accentColor : .secondary)
                        .monospacedDigit()
                        .frame(width: 38, alignment: .leading)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title.bitefm_sanitizedDisplayLine)
                            .font(.subheadline)
                            .fontWeight(isCurrentSong ? .bold : .medium)
                            .foregroundColor(isCurrentSong ? .accentColor : .primary)
                        Text(song.artist.bitefm_sanitizedDisplayLine)
                            .font(.caption)
                            .foregroundColor(isCurrentSong ? .accentColor.opacity(0.8) : .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .contextMenu {
                    Button {
                        playFromSong()
                    } label: {
                        Label("Von hier abspielen", systemImage: "play.circle")
                    }
                    Button {
                        copySongToPasteboard(artist: song.artist, title: song.title)
                    } label: {
                        Label("Titel kopieren", systemImage: "doc.on.doc")
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
        }
    }
    
    private func playFromSong() {
        if playerManager.currentItem?.id == archiveItem.id {
            playerManager.seek(to: Double(song.time))
        } else {
            playerManager.play(item: archiveItem, playlist: playlist, initialPosition: Double(song.time))
        }
    }

    private func copySongToPasteboard(artist: String, title: String) {
        let line = "\(artist) – \(title)"
        #if os(iOS)
        UIPasteboard.general.string = line
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line, forType: .string)
        #endif
    }
}
