import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - iPhone mini bar

/// `.tabAccessory`: use with `tabViewBottomAccessory` — system supplies Liquid Glass / tab-bar-matched chrome (iOS 18+).
/// `.safeAreaInsetRow`: use with `safeAreaInset` fallback — own divider + bar material.
enum MiniPlayerBarChrome {
    case tabAccessory
    case safeAreaInsetRow
}

struct MiniPlayerBarView: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    /// Prefer labeling at call sites: `MiniPlayerBarView(chrome: .tabAccessory, onExpand: { … })` (avoids trailing-closure ambiguity with `chrome:`).
    var onExpand: () -> Void
    var chrome: MiniPlayerBarChrome = .safeAreaInsetRow
    var namespace: Namespace.ID? = nil

    var body: some View {
        let cornerRadius: CGFloat = chrome == .tabAccessory ? 18 : 16
        switch chrome {
        case .tabAccessory:
            miniRow
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background {
                    NowPlayingMatchedSurfaceBackground(
                        namespace: namespace,
                        cornerRadius: cornerRadius,
                        // `tabViewBottomAccessory` dupliziert die View intern (Layout/Transitions).
                        // Zusammen mit matchedGeometry kann das zu "multiple isSource: true" Warnungen führen.
                        // Für die Accessory-Variante lassen wir daher matched-geometry als Source aus.
                        isMatchedGeometrySource: false,
                        materialFallback: nil
                    )
                }
        case .safeAreaInsetRow:
            VStack(spacing: 0) {
                Divider()
                miniRow
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background {
                        NowPlayingMatchedSurfaceBackground(
                            namespace: namespace,
                            cornerRadius: cornerRadius,
                            isMatchedGeometrySource: true,
                            materialFallback: AnyView(Rectangle().fill(Material.bar))
                        )
                    }
            }
        }
    }

    private var miniRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onExpand) {
                VStack(alignment: .leading, spacing: 4) {
                    PlayerBarMetadataBlock()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Wiedergabe öffnen")
            .accessibilityHint("Zeigt die aktuelle Wiedergabe mit Details und Steuerung.")

            Button(action: { playerManager.togglePlayPause() }) {
                let imageName: String = {
                    if playerManager.isPlaying {
                        return playerManager.isLive ? "stop.circle.fill" : "pause.circle.fill"
                    }
                    return "play.circle.fill"
                }()
                Image(systemName: imageName)
                    .font(.system(size: 34))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playerManager.isPlaying ? "Pause" : "Abspielen")
            .frame(width: 44, height: 44)
        }
    }
}

// MARK: - Expanded sheet (full Now Playing)

struct ExpandedNowPlayingView: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @EnvironmentObject private var apiClient: APIClient
    @Environment(\.dismiss) private var dismiss
    var onClose: (() -> Void)? = nil
    var namespace: Namespace.ID? = nil
    var allowsSwipeToDismiss: Bool = false
    /// Bewusst `@State` (statt `@GestureState`): beim Loslassen einer erfolgreichen Dismiss-Geste soll
    /// der Offset NICHT auf 0 zurückspringen — der `fullScreenCover`-Dismiss läuft dann von der
    /// aktuellen Position weiter, sodass es keine sichtbare Doppel-Animation gibt.
    @State private var dismissDragTranslation: CGFloat = 0
    /// Wird einmalig beim Start jeder Drag-Geste festgelegt. Verhindert, dass die Dismiss-Geste
    /// mitten im Scrollen aktiv wird, sobald der Inhalt seinen Top-Anschlag erreicht.
    @State private var dismissEligibility: DismissEligibility = .undecided
    @State private var isPrimaryScrollAtTop: Bool = true

    private enum DismissEligibility {
        case undecided
        case eligible
        case ineligible
    }

    /// Größere Steuerung im Sheet „Wiedergabe“ (+35 % gegenüber Player-Leiste).
    private static let expandedTransportIconScale: CGFloat = 1.35

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(overlayBackgroundColor)
                    .ignoresSafeArea()

                NowPlayingMatchedSurfaceBackground(
                    namespace: namespace,
                    cornerRadius: presentationCornerRadius,
                    isMatchedGeometrySource: false,
                    materialFallback: AnyView(
                        Rectangle().fill(isOverlayMode ? overlayBackgroundColor : Color.clear)
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                NavigationStack {
                    Group {
                        if playerManager.currentItem != nil {
                            expandedArchiveBody
                        } else if playerManager.isLive {
                            expandedLiveBody
                        } else {
                            ContentUnavailableView(
                                "Nichts in Wiedergabe",
                                systemImage: "music.note",
                                description: Text("Starten Sie eine Sendung oder einen Livestream.")
                            )
                        }
                    }
                    .navigationTitle("Wiedergabe")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fertig") { close() }
                        }
                    }
                }
                // Den Clip nur anwenden, wenn wir wirklich gerundete Ecken brauchen (iPad-Sheet etc.).
                // Bei `presentationCornerRadius == 0` (iPhone-Vollbild) würde `RoundedRectangle(cornerRadius: 0)`
                // den Stack auf seine Content-Frame clippen — und damit den per `.ignoresSafeArea(.bottom)`
                // erweiterten Steuerungs-Hintergrund im Home-Indikator-Bereich abschneiden, was als harte
                // Kante zwischen Buttonbereich und dem schmalen Streifen darunter sichtbar wird.
                .modifier(NowPlayingPresentationClip(cornerRadius: presentationCornerRadius))
            }
            #if os(iOS)
            .contentShape(RoundedRectangle(cornerRadius: presentationCornerRadius, style: .continuous))
            .offset(y: overlayDismissOffset)
            .simultaneousGesture(
                dismissDragGesture(containerHeight: proxy.size.height),
                including: allowsSwipeToDismiss ? .gesture : .none
            )
            #endif
        }
        .onChange(of: playerManager.currentItem?.id) { _, _ in
            dismissIfNothingToShow()
        }
        .onChange(of: playerManager.isLive) { _, _ in
            dismissIfNothingToShow()
        }
    }

    private func dismissIfNothingToShow() {
        if playerManager.currentItem == nil && !playerManager.isLive {
            close()
        }
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    // Top-edge swipe-down dismiss for full-screen iPhone presentation.
    // The gesture only starts near the top to avoid conflicts with vertical scrolling in content.
    #if os(iOS)
    private var overlayDismissOffset: CGFloat {
        guard allowsSwipeToDismiss else { return 0 }
        return max(0, dismissDragTranslation)
    }

    private func dismissDragGesture(containerHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard allowsSwipeToDismiss else { return }
                // Eligibility wird genau einmal pro Geste festgelegt — am Geste-Start.
                // Dadurch kann sich „durchscrollen bis zum Top und dann weiter wischen“ NICHT mittendrin
                // in einen Dismiss verwandeln. Erst die nächste, neu gestartete Geste am Top dismissed.
                if dismissEligibility == .undecided {
                    dismissEligibility = canStartDismissGesture(
                        startY: value.startLocation.y,
                        containerHeight: containerHeight
                    ) ? .eligible : .ineligible
                }
                guard dismissEligibility == .eligible else { return }
                dismissDragTranslation = max(0, value.translation.height)
            }
            .onEnded { value in
                let wasEligible = dismissEligibility == .eligible
                dismissEligibility = .undecided
                guard allowsSwipeToDismiss, wasEligible else {
                    resetDismissTranslation()
                    return
                }
                let translation = value.translation.height
                let lateral = abs(value.translation.width)
                if translation > 110, lateral < 90 {
                    // Offset bewusst NICHT zurücksetzen: Der `fullScreenCover`-Dismiss läuft jetzt
                    // von der aktuellen, nach unten verschobenen Position weiter — eine durchgehende
                    // Animation, kein Sprung-zurück + zweite Slide-Animation.
                    close()
                } else {
                    resetDismissTranslation()
                }
            }
    }

    private func resetDismissTranslation() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            dismissDragTranslation = 0
        }
    }

    /// Dismiss-Geste soll im oberen Bereich (Sendungsdetails) NIE starten, damit dort ausschließlich
    /// gescrollt wird. Im unteren Bereich (Buttons) darf die Dismiss-Geste starten.
    private func canStartDismissGesture(startY: CGFloat, containerHeight: CGFloat) -> Bool {
        let controlsRegionStartY = max(0, containerHeight - Self.expandedBottomBarDismissRegionHeight)
        return startY >= controlsRegionStartY
    }
    #endif

    private var isOverlayMode: Bool {
        onClose != nil
    }

    private var presentationCornerRadius: CGFloat {
        (isOverlayMode || allowsSwipeToDismiss) ? 0 : 22
    }

    private var overlayBackgroundColor: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }

    @ViewBuilder
    private var expandedArchiveBody: some View {
        if let item = playerManager.currentItem {
            BroadcastDetailView(
                item: item,
                showsPrimaryPlayAction: false,
                scrollAtTop: $isPrimaryScrollAtTop
            )
            // Controls als echtes Safe-Area-Inset, damit die Details nicht hinter den Buttons verschwinden
            // und der Gradient nur im Controls-Bereich beginnt.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    expandedControlsChrome(live: false)
                }
        }
    }

    private var expandedLiveBody: some View {
        ExpandedLiveNowPlayingContent(scrollAtTop: $isPrimaryScrollAtTop)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                expandedControlsChrome(live: true)
            }
    }

    /// Live: undurchsichtiger Hintergrund bis in die untere Safe Area — vermeidet den schmalen grauen Rand um die Blur-Leiste bei nur einem Stop-Button.
    private func expandedControlsChrome(live: Bool) -> some View {
        Group {
            #if os(iOS)
            PlaybackControlsStack(
                compactTimeline: true,
                keyboardShortcut: false,
                spacing: 10,
                transportIconScale: Self.expandedTransportIconScale,
                showsAirPlayRoutePicker: true
            )
            #else
            PlaybackControlsStack(
                compactTimeline: true,
                keyboardShortcut: false,
                spacing: 10,
                transportIconScale: Self.expandedTransportIconScale
            )
            #endif
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background { expandedBottomBarBackground(live: live) }
    }

    /// Dismiss-Region am unteren Bildschirmrand (Buttons + Seekbar + Padding).
    private static let expandedBottomBarDismissRegionHeight: CGFloat = 240

    /// Visuelle Größe des Play/Pause Icons im Expanded Sheet.
    /// Basiswert aus `PlaybackTransportButtons` (play/pause): 28pt, skaliert im Expanded Sheet.
    private static var expandedPlayButtonIconSide: CGFloat { 28 * expandedTransportIconScale }

    /// Untere Kante des Gradients (ab hier ist die Bar voll deckend).
    /// Soll **oberhalb** des Play-Buttons enden.
    private static var expandedBottomBarFadeEnd: CGFloat {
        // Play/Pause Hit-Area (56*s) + top padding (10) -> grob: bis knapp oberhalb der Play-Taste.
        // Wir nutzen die Icon-Seite als stabilen Proxy, da die Hit-Area intern ist.
        expandedPlayButtonIconSide + 8
    }

    /// Höhe des Gradients nach oben. Größer = längerer weicher Übergang,
    /// ohne die untere Kante (`expandedBottomBarFadeEnd`) zu verschieben.
    private static var expandedBottomBarFadeHeight: CGFloat { 180 }

    @ViewBuilder
    private func expandedBottomBarBackground(live: Bool) -> some View {
#if os(iOS)
        // Liquid Glass:
        // - Hintergrund (Material) ist bis unten voll deckend, inkl. Home-Indikator-Bereich.
        // - Maske blendet nur im oberen Bereich weich ein, so dass Details „hineinlaufen“ können.
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask(expandedBottomBarMask)
            .ignoresSafeArea(edges: .bottom)
#else
        Rectangle()
            .fill(Material.bar)
#endif
    }

#if os(iOS)
    private var expandedBottomBarMask: some View {
        GeometryReader { proxy in
            let fadeEnd = Self.expandedBottomBarFadeEnd
            let fadeHeight = Self.expandedBottomBarFadeHeight
            let height = max(1, proxy.size.height)
            let t0 = max(0, min(1, (fadeEnd - fadeHeight) / height))
            let t1 = max(0, min(1, fadeEnd / height))

            // Single gradient mask to avoid a visible seam where two mask layers meet.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: t0),
                    .init(color: .black, location: t1),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
#endif
}

/// Wendet `RoundedRectangle`-Clip nur an, wenn ein Radius > 0 erforderlich ist.
/// Bei Radius 0 würde das Clip den NavigationStack auf seine Content-Frame begrenzen
/// und damit per `ignoresSafeArea` erweiterte Hintergründe (z. B. die Steuerungsleiste im
/// Home-Indikator-Bereich) abschneiden.
private struct NowPlayingPresentationClip: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if cornerRadius > 0 {
            content.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
        }
    }
}

private struct NowPlayingSurfaceMatchModifier: ViewModifier {
    let namespace: Namespace.ID?
    let cornerRadius: CGFloat
    let isSource: Bool

    func body(content: Content) -> some View {
        if let namespace {
            content
                .matchedGeometryEffect(
                    id: NowPlayingSurfaceMatchID.surface,
                    in: namespace,
                    isSource: isSource
                )
        } else {
            content
        }
    }
}

private enum NowPlayingSurfaceMatchID {
    static let surface: String = "NowPlayingSurface"
}

private struct NowPlayingMatchedSurfaceBackground: View {
    let namespace: Namespace.ID?
    let cornerRadius: CGFloat
    let isMatchedGeometrySource: Bool
    let materialFallback: AnyView?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if let materialFallback {
                materialFallback
                    .clipShape(shape)
            } else {
                Color.clear
                    .clipShape(shape)
            }
        }
        .modifier(
            NowPlayingSurfaceMatchModifier(
                namespace: namespace,
                cornerRadius: cornerRadius,
                isSource: isMatchedGeometrySource
            )
        )
    }
}

// MARK: - Live metadata (no ArchiveItem)

private struct ExpandedLiveNowPlayingContent: View {
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var scrollAtTop: Binding<Bool>? = nil

    private var artworkSide: CGFloat { horizontalSizeClass == .compact ? 200 : 260 }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                topScrollMarker
                ZStack {
                    fallbackCoverIcon

                    if let streamType = playerManager.currentStreamType,
                       let imageURL = apiClient.liveMetadata?.artistImageURL[streamType.rawValue],
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

                VStack(spacing: 8) {
                    if let streamType = playerManager.currentStreamType,
                       let currentTrack = apiClient.liveMetadata?.tracks[streamType.rawValue]?.first {
                        Text(currentTrack.decodedBasicHTMLEntities)
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                    }

                    if let streamType = playerManager.currentStreamType,
                       let currentShow = apiClient.liveMetadata?.currentShowTitle[streamType.rawValue],
                       !currentShow.isEmpty {
                        Text(currentShow)
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if let streamType = playerManager.currentStreamType,
                       let currentSubtitle = apiClient.liveMetadata?.currentShowSubtitle[streamType.rawValue],
                       !currentSubtitle.isEmpty {
                        Text(currentSubtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if let streamType = playerManager.currentStreamType,
                       let currentTime = apiClient.liveMetadata?.currentShowTime[streamType.rawValue],
                       !currentTime.isEmpty {
                        Text(currentTime)
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                .padding(.horizontal)

                if let streamType = playerManager.currentStreamType {
                    Text("Stream: \(streamType.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .coordinateSpace(name: "ExpandedLiveScrollSpace")
        .onPreferenceChange(ScrollTopOffsetPreferenceKey.self) { minY in
            scrollAtTop?.wrappedValue = minY >= -6
        }
        .onAppear {
            apiClient.startLiveMetadataPolling()
        }
        .onDisappear {
            // Live-Stream läuft weiter (Mini-Player / andere UI): Metadaten-Polling nicht beenden.
            if !playerManager.isLive {
                apiClient.stopLiveMetadataPolling()
            }
        }
    }

    private var topScrollMarker: some View {
        Color.clear
            .frame(height: 0)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: ScrollTopOffsetPreferenceKey.self,
                            value: proxy.frame(in: .named("ExpandedLiveScrollSpace")).minY
                        )
                }
            )
    }

    private var fallbackCoverIcon: some View {
        Image(systemName: "music.note.list")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 64, height: 64)
            .foregroundColor(.secondary)
            .padding(68)
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(width: artworkSide, height: artworkSide)
    }
}

private struct ScrollTopOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
