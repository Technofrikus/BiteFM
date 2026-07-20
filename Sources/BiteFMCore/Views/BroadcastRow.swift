import SwiftUI

/// Narrow, value-type snapshot of the `APIClient` state a `BroadcastRow` actually needs
/// (favorite/played flags). Rows observe this instead of the whole `APIClient` as an
/// `@EnvironmentObject`, so the 60-second `liveMetadata` poll (and other unrelated
/// `@Published` changes) no longer re-render every visible row.
struct FavoritePlayedState: Equatable {
    let favoriteSlugs: Set<String>
    let favoriteShowIDs: Set<Int>
    let listenedShowIDs: Set<Int>

    @MainActor
    static func from(_ api: APIClient) -> FavoritePlayedState {
        FavoritePlayedState(
            favoriteSlugs: api.favoriteSlugs,
            favoriteShowIDs: api.favoriteShowIDs,
            listenedShowIDs: api.listenedShowIDs
        )
    }
}

/// Builds a `BroadcastRow` wired to a narrow `FavoritePlayedState` snapshot instead of the
/// full `APIClient`. Pass the current state from the parent (recomputed only when the three
/// relevant `APIClient` sets change), so unrelated `APIClient` publishes don't re-render rows.
@MainActor
func makeBroadcastRow(
    item: ArchiveItem,
    showShowTitle: Bool = true,
    showHeart: Bool = true,
    onFavoriteTap: (() -> Void)? = nil,
    metaLineSizeSuffix: String? = nil,
    favoritePlayed: FavoritePlayedState,
    selectedItemForDetail: Binding<ArchiveItem?>,
    isInspectorPresented: Binding<Bool>
) -> BroadcastRow {
    BroadcastRow(
        item: item,
        showShowTitle: showShowTitle,
        showHeart: showHeart,
        onFavoriteTap: onFavoriteTap,
        metaLineSizeSuffix: metaLineSizeSuffix,
        favoritePlayed: favoritePlayed,
        selectedItemForDetail: selectedItemForDetail,
        isInspectorPresented: isInspectorPresented
    )
}

struct BroadcastRow: View {
    let item: ArchiveItem
    var showShowTitle: Bool = true
    var showHeart: Bool = true
    /// When set, the heart is tappable; otherwise read-only indicator.
    var onFavoriteTap: (() -> Void)? = nil
    /// Rechts in der Datumszeile (vor dem Info-Button), z. B. feste MB aus dem Download-Tab.
    var metaLineSizeSuffix: String? = nil
    /// Narrow snapshot of the favorite/played state this row needs. Replaces observing the
    /// whole `APIClient` (which re-rendered every row on the 60 s `liveMetadata` poll).
    let favoritePlayed: FavoritePlayedState

    @EnvironmentObject private var activePlayback: ActivePlaybackStore
    #if os(iOS)
    /// Used only for actions (start / cancel). Rows do NOT observe the whole manager's
    /// `objectWillChange` — that would re-render every row on each progress tick. Instead each
    /// row subscribes (via `onReceive`) to its own terminID's publisher on the manager, so only
    /// the actively downloading row re-renders.
    @EnvironmentObject private var downloadManager: IOSDownloadManager
    /// This row's download UI snapshot, kept in sync from the manager's per-terminID publisher.
    @State private var downloadSnap: EpisodeDownloadUISnapshot
    #endif
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Binding var selectedItemForDetail: ArchiveItem?
    @Binding var isInspectorPresented: Bool

    init(
        item: ArchiveItem,
        showShowTitle: Bool = true,
        showHeart: Bool = true,
        onFavoriteTap: (() -> Void)? = nil,
        metaLineSizeSuffix: String? = nil,
        favoritePlayed: FavoritePlayedState,
        selectedItemForDetail: Binding<ArchiveItem?>,
        isInspectorPresented: Binding<Bool>
    ) {
        self.item = item
        self.showShowTitle = showShowTitle
        self.showHeart = showHeart
        self.onFavoriteTap = onFavoriteTap
        self.metaLineSizeSuffix = metaLineSizeSuffix
        self.favoritePlayed = favoritePlayed
        self._selectedItemForDetail = selectedItemForDetail
        self._isInspectorPresented = isInspectorPresented
        #if os(iOS)
        // Seed the local snapshot from the manager's current value so the row shows correct
        // state before the first publisher emission. The `onReceive` below keeps it in sync.
        _downloadSnap = State(wrappedValue: IOSDownloadManager.shared.uiSnapshot(for: item.terminID)
            ?? EpisodeDownloadUISnapshot(status: .queued, progress: 0, expectedSizeBytes: 0, exists: false))
        #endif
    }

    private enum RowPlaybackVisualState {
        case idle
        case preparing
        case playing
    }

    private var rowPlaybackState: RowPlaybackVisualState {
        if activePlayback.isActivePreparing, activePlayback.activeTerminID == item.id {
            return .preparing
        }
        if activePlayback.activeTerminID == item.id, activePlayback.isActivePlaying {
            return .playing
        }
        return .idle
    }

    private var isRowHighlighted: Bool {
        switch rowPlaybackState {
        case .preparing, .playing:
            return true
        case .idle:
            return false
        }
    }

    private var isPlaying: Bool {
        rowPlaybackState == .playing
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    /// Visible icon size stays small; the hit target remains wider than the glyph.
    private let rowAccessoryBox: CGFloat = 18

    private var rowAccessoryHitBox: CGFloat {
        #if os(iOS)
        return 28
        #else
        return 28
        #endif
    }

    private var contentVerticalPadding: CGFloat { 6 }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isRowHighlighted {
                Capsule()
                    .fill(Color.accentColor.opacity(rowPlaybackState == .preparing ? 0.55 : 1))
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .accessibilityHidden(true)
            }
            Group {
                HStack(alignment: .top, spacing: 2) {
                    playbackTapArea
                    detailInfoButton
                }
            }
            .padding(.vertical, contentVerticalPadding)
            .padding(.horizontal, 8)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 12))
        #if os(iOS)
        // Subscribe to THIS terminID's publisher only. Progress ticks for other downloads do
        // not touch this row. This is the reliable alternative to per-row `@StateObject`, which
        // is flaky inside `List`/`ForEach` rows.
        .onReceive(IOSDownloadManager.shared.publisher(for: item.terminID)) { newSnap in
            downloadSnap = newSnap
        }
        #endif
    }

    /// Datum und optionale Größe bleiben oben; kompakte Status-/Aktionsicons sitzen rechts in derselben Zeile.
    private var playbackTapArea: some View {
        Button(action: playAndRevealIfNeeded) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    // Zeile 1: Datum & Meta
                    HStack(spacing: 6) {
                        Text(dateLineString)
                            .multilineTextAlignment(.leading)
                        if let extra = resolvedMetaLineSizeSuffix {
                            Text(extra)
                        }
                        if rowPlaybackState == .preparing {
                            Text("lädt …")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(isRowHighlighted ? .accentColor.opacity(0.75) : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                    // Zeile 2: Titel
                    Text((showShowTitle ? item.sendungTitel : item.subtitle).bitefm_sanitizedDisplayLine)
                        .font(.headline)
                        .foregroundColor(isRowHighlighted ? .accentColor : .primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    // Zeile 3: Untertitel (optional)
                    if showShowTitle {
                        Text(item.subtitle)
                            .font(.subheadline)
                            .foregroundColor(isRowHighlighted ? .accentColor.opacity(0.8) : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())

                inlineStatusControls
                    .offset(y: -5) // Zentrierung der 28pt Icons zur ~14pt Caption-Zeile
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityHint("Spielt diese Ausgabe ab.")
        .opacity(favoritePlayed.listenedShowIDs.contains(item.terminID) && !isRowHighlighted ? 0.65 : 1.0)
    }

    private var inlineStatusControls: some View {
        HStack(alignment: .center, spacing: 2) {
            if rowPlaybackState == .preparing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: rowAccessoryBox, height: rowAccessoryBox)
                    .frame(width: rowAccessoryHitBox, height: rowAccessoryHitBox)
                    .accessibilityLabel("Wiedergabe wird vorbereitet")
            } else if rowPlaybackState == .playing {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: rowAccessoryBox, height: rowAccessoryBox)
                    .frame(width: rowAccessoryHitBox, height: rowAccessoryHitBox)
                    .accessibilityLabel("Wird abgespielt")
            }
            if favoritePlayed.listenedShowIDs.contains(item.terminID) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: rowAccessoryBox, height: rowAccessoryBox)
                    .frame(width: rowAccessoryHitBox, height: rowAccessoryHitBox)
                    .accessibilityLabel("Bereits gehört")
            }
            #if os(iOS)
            downloadLeadingControl
            #endif
            heartControl
        }
        .frame(height: rowAccessoryHitBox, alignment: .center)
    }

    private var dateLineString: String {
        let timePart = item.startTime.isEmpty ? "" : "| \(item.startTime) - \(item.endTime)"
        let s = "\(item.datumDe) \(timePart)"
        return s.trimmingCharacters(in: .whitespaces)
    }

    #if os(iOS)
    private var resolvedMetaLineSizeSuffix: String? {
        if let metaLineSizeSuffix, !metaLineSizeSuffix.isEmpty { return metaLineSizeSuffix }
        guard downloadSnap.exists, downloadSnap.expectedSizeBytes > 0 else { return nil }
        switch downloadSnap.status {
        case .preparing, .queued, .downloading:
            return Self.formatMegabytes(downloadSnap.expectedSizeBytes, tildePrefix: true)
        default:
            return nil
        }
    }
    #else
    private var resolvedMetaLineSizeSuffix: String? { metaLineSizeSuffix }
    #endif

    private static func formatMegabytes(_ bytes: Int64, tildePrefix: Bool) -> String? {
        guard bytes > 0 else { return nil }
        let mb = Double(bytes) / (1024 * 1024)
        let core: String
        if mb >= 100 { core = String(format: "%.0f MB", mb) }
        else { core = String(format: "%.1f MB", mb) }
        return tildePrefix ? "~\(core)" : core
    }

    private var detailInfoButton: some View {
        let isSelected = selectedItemForDetail?.id == item.id && isInspectorPresented
        return Button(action: toggleDetailPresentation) {
            Image(systemName: "info.circle")
                .font(.system(size: 18))
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                .frame(width: rowAccessoryHitBox, height: rowAccessoryHitBox)
                .background(isSelected ? Color.accentColor : Color.clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "Details schließen" : "Details")
        .offset(y: -5) // Align with inlineStatusControls (same -5 lift to the caption line)
    }

    @ViewBuilder
    private var heartControl: some View {
        if showHeart {
            let isFav = showShowTitle
                ? FavoriteStateLogic.isFavoriteArchiveItem(
                    sendungSlug: item.sendungSlug,
                    terminSlug: item.terminSlug,
                    sendungTitel: item.sendungTitel,
                    terminID: item.terminID,
                    favoriteSlugs: favoritePlayed.favoriteSlugs,
                    favoriteShowIDs: favoritePlayed.favoriteShowIDs
                )
                : FavoriteStateLogic.isEpisodeFavorite(
                    terminID: item.terminID,
                    terminSlug: item.terminSlug,
                    favoriteShowIDs: favoritePlayed.favoriteShowIDs,
                    favoriteSlugs: favoritePlayed.favoriteSlugs
                )
            if let onFavoriteTap {
                Button(action: onFavoriteTap) {
                    Image(systemName: isFav ? "heart.fill" : "heart")
                        .font(.body)
                        .foregroundStyle(isFav ? Color.pink : Color.secondary)
                        .frame(width: rowAccessoryBox, height: rowAccessoryBox)
                }
                .buttonStyle(.plain)
                .frame(width: rowAccessoryHitBox, height: rowAccessoryHitBox)
                .accessibilityLabel(isFav ? "Favorit entfernen" : "Als Favorit speichern")
                #if os(macOS)
                .help(isFav ? "Favorit entfernen" : "Als Favorit speichern")
                #endif
            } else if isFav {
                Image(systemName: "heart.fill")
                    .font(.body)
                    .foregroundStyle(.pink)
                    .frame(width: rowAccessoryBox, height: rowAccessoryBox)
                    .frame(width: rowAccessoryHitBox, height: rowAccessoryHitBox)
                    .accessibilityLabel("Favorit")
            }
        }
    }

    private func toggleDetailPresentation() {
        if isInspectorPresented, selectedItemForDetail?.id == item.id {
            selectedItemForDetail = nil
            isInspectorPresented = false
        } else {
            selectedItemForDetail = item
            isInspectorPresented = true
        }
    }

    private func playAndRevealIfNeeded() {
        AudioPlayerManager.shared.play(item: item)
        if isInspectorPresented {
            selectedItemForDetail = item
        }
    }

    #if os(iOS)
    /// iOS-only: download / Fortschritt / erneuter Download bei Fehler; nach Erfolg Play-Hinweis (Hauptbereich spielt ebenfalls ab).
    @ViewBuilder
    private var downloadLeadingControl: some View {
        let snap = downloadSnap
        Group {
            if snap.exists {
                switch snap.status {
                case .downloaded:
                    Button {
                        AudioPlayerManager.shared.play(item: item)
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: rowAccessoryBox, height: rowAccessoryBox)
                    }
                    .buttonStyle(.plain)
                    .frame(width: rowAccessoryHitBox, height: rowAccessoryHitBox)
                    .accessibilityLabel("Lokal abspielen")
                case .downloading:
                    Button {
                        downloadManager.removeDownload(for: item.terminID)
                    } label: {
                        downloadRingProgress(progress: snap.progress)
                    }
                    .buttonStyle(.plain)
                    .frame(width: rowAccessoryHitBox, height: rowAccessoryHitBox)
                    .accessibilityLabel("Download abbrechen")
                case .queued, .preparing:
                    Button {
                        downloadManager.removeDownload(for: item.terminID)
                    } label: {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: rowAccessoryBox, height: rowAccessoryBox)
                    }
                    .buttonStyle(.plain)
                    .frame(width: rowAccessoryHitBox, height: rowAccessoryHitBox)
                    .accessibilityLabel("Download abbrechen")
                case .failed:
                    Button {
                        Task { await downloadManager.startDownload(for: item) }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.body)
                            .foregroundStyle(.orange)
                            .frame(width: rowAccessoryBox, height: rowAccessoryBox)
                    }
                    .buttonStyle(.plain)
                    .frame(width: rowAccessoryHitBox, height: rowAccessoryHitBox)
                    .accessibilityLabel("Download erneut versuchen")
                }
            } else {
                Button {
                    Task { await downloadManager.startDownload(for: item) }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: rowAccessoryBox, height: rowAccessoryBox)
                }
                .buttonStyle(.plain)
                .frame(width: rowAccessoryHitBox, height: rowAccessoryHitBox)
                .accessibilityLabel("Herunterladen")
            }
        }
    }

    /// Kreisförmiger Ring-Fortschritt für aktive Downloads.
    private func downloadRingProgress(progress: Double) -> some View {
        let p = min(1, max(0, progress))
        return ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.28), lineWidth: 2.2)
            Circle()
                .trim(from: 0, to: CGFloat(p))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: rowAccessoryBox, height: rowAccessoryBox)
    }
    #endif
}
