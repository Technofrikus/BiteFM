import SwiftUI

struct BroadcastRow: View {
    let item: ArchiveItem
    var showShowTitle: Bool = true
    var showHeart: Bool = true
    /// When set, the heart is tappable; otherwise read-only indicator.
    var onFavoriteTap: (() -> Void)? = nil
    /// Rechts in der Datumszeile (vor dem Info-Button), z. B. feste MB aus dem Download-Tab.
    var metaLineSizeSuffix: String? = nil

    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var activePlayback: ActivePlaybackStore
    #if os(iOS)
    @EnvironmentObject private var downloadManager: IOSDownloadManager
    #endif
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Binding var selectedItemForDetail: ArchiveItem?
    @Binding var isInspectorPresented: Bool

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
                if isCompact {
                    HStack(alignment: .top, spacing: 10) {
                        playbackTapArea
                        detailInfoButton
                    }
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        playbackTapArea
                        Divider()
                            .frame(height: 28)
                            .padding(.horizontal, 6)
                        detailInfoButton
                    }
                }
            }
            .padding(.vertical, contentVerticalPadding)
            .padding(.horizontal, 8)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 12))
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
        .opacity(apiClient.isPlayed(item: item) && !isRowHighlighted ? 0.65 : 1.0)
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
            if apiClient.isPlayed(item: item) {
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
        guard let snap = downloadManager.uiSnapshot(for: item.terminID) else { return nil }
        guard snap.expectedSizeBytes > 0 else { return nil }
        switch snap.status {
        case .preparing, .queued, .downloading:
            return Self.formatMegabytes(snap.expectedSizeBytes, tildePrefix: true)
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
    }

    @ViewBuilder
    private var heartControl: some View {
        if showHeart {
            let isFav = showShowTitle ? apiClient.isFavorite(item: item) : apiClient.isEpisodeFavorite(item: item)
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
        let snap = downloadManager.uiSnapshot(for: item.terminID)
        Group {
            if let snap {
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
