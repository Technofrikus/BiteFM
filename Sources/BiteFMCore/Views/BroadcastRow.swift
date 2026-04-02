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
    @EnvironmentObject private var playerManager: AudioPlayerManager
    #if os(iOS)
    @EnvironmentObject private var downloadManager: IOSDownloadManager
    #endif
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Binding var selectedItemForDetail: ArchiveItem?
    @Binding var isInspectorPresented: Bool

    var isPlaying: Bool {
        playerManager.currentItem?.id == item.id && playerManager.isPlaying
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    /// Visual weight aligned with the download control (`.body` SF Symbol in a fixed hit target).
    private let rowAccessoryBox: CGFloat = 22

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isPlaying {
                Capsule()
                    .fill(Color.accentColor)
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
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
        }
        .listRowInsets(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 12))
    }

    /// Icons, Datum und optionale Größe in **einer** Zeile (Datum rechts, vor dem Info-Button); Titel darunter volle Breite.
    private var playbackTapArea: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 6) {
                #if os(iOS)
                downloadLeadingControl
                #endif
                heartControl
                if !isPlaying && apiClient.isPlayed(item: item) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: rowAccessoryBox, height: rowAccessoryBox)
                }
                HStack(spacing: 6) {
                    Text(dateLineString)
                        .multilineTextAlignment(.leading)
                    if let extra = resolvedMetaLineSizeSuffix {
                        Text(extra)
                    }
                }
                .font(.caption)
                .foregroundColor(isPlaying ? .accentColor.opacity(0.75) : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
            Text((showShowTitle ? item.sendungTitel : item.subtitle).bitefm_sanitizedDisplayLine)
                .font(.headline)
                .foregroundColor(isPlaying ? .accentColor : .primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if showShowTitle {
                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundColor(isPlaying ? .accentColor.opacity(0.8) : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .opacity(apiClient.isPlayed(item: item) && !isPlaying ? 0.65 : 1.0)
        .onTapGesture {
            playerManager.play(item: item)
            if isInspectorPresented {
                selectedItemForDetail = item
            }
        }
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
                .frame(width: 40, height: 40)
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
                        .foregroundColor(isFav ? .red : .secondary)
                        .frame(width: rowAccessoryBox, height: rowAccessoryBox)
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .help(isFav ? "Favorit entfernen" : "Als Favorit speichern")
                #endif
            } else if isFav {
                Image(systemName: "heart.fill")
                    .font(.body)
                    .foregroundColor(.red)
                    .frame(width: rowAccessoryBox, height: rowAccessoryBox)
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
                        playerManager.play(item: item)
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.body)
                            .foregroundStyle(.green)
                            .frame(width: rowAccessoryBox, height: rowAccessoryBox)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Lokal abspielen")
                case .downloading:
                    downloadRingProgress(progress: snap.progress)
                        .accessibilityLabel("Wird heruntergeladen")
                case .queued, .preparing:
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: rowAccessoryBox, height: rowAccessoryBox)
                        .accessibilityLabel("Download wird vorbereitet")
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
