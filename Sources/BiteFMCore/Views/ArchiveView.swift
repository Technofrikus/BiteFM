import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct ArchiveView: View {
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var searchText = ""
    @State private var hoveredIndexSymbol: String?
    @State private var lastIndexDragSymbol: String?
    @State private var favoritesOnly = false

    private var showLetterIndexStrip: Bool {
        #if os(macOS)
        return true
        #else
        return !dynamicTypeSize.isAccessibilitySize
        #endif
    }

    private var usesOverlayLetterIndex: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }
    
    private var filteredShows: [Show] {
        var list = apiClient.shows
        if favoritesOnly {
            list = list.filter { apiClient.isFavorite(show: $0) }
        }
        if searchText.isEmpty {
            return list
        }
        return list.filter {
            $0.titel.localizedCaseInsensitiveContains(searchText) ||
            $0.untertitel.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// Sendungen nach Anfangsbuchstaben; Sortierung: **#** (Ziffern & Sonstiges) zuerst, dann A–Z.
    private var letterSections: [(letter: String, shows: [Show])] {
        let shows = filteredShows
        let grouped = Dictionary(grouping: shows) { ArchiveSectionHelpers.indexLetter(forShowTitle: $0.titel) }
        let de = Locale(identifier: "de_DE")
        let keys = grouped.keys.sorted { lhs, rhs in
            let pL = letterSortRank(lhs)
            let pR = letterSortRank(rhs)
            if pL != pR { return pL < pR }
            return lhs.compare(rhs, options: [.caseInsensitive], range: nil, locale: de) == .orderedAscending
        }
        return keys.map { letter in
            let list = (grouped[letter] ?? []).sorted {
                $0.titel.localizedCaseInsensitiveCompare($1.titel) == .orderedAscending
            }
            return (letter, list)
        }
    }
    
    /// 0 = „#“, 1 = Buchstaben
    private func letterSortRank(_ key: String) -> Int {
        key == "#" ? 0 : 1
    }
    
    private var availableSectionIDs: Set<String> {
        Set(letterSections.map(\.letter))
    }
    
    /// Index: **#** zuerst, dann A–Z, dann weitere Buchstaben (Ä, Ö, …).
    private var indexStripSymbols: [String] {
        let available = availableSectionIDs
        #if os(iOS)
        if usesOverlayLetterIndex {
            return letterSections.map(\.letter)
        }
        #endif
        let lettersAZ = (65...90).map { String(UnicodeScalar($0)!) }
        var rows: [String] = ["#"]
        rows.append(contentsOf: lettersAZ)
        let fixedSet = Set(rows)
        let extras = available.subtracting(fixedSet).sorted { lhs, rhs in
            lhs.compare(rhs, options: [.caseInsensitive], range: nil, locale: Locale(identifier: "de_DE")) == .orderedAscending
        }
        rows.append(contentsOf: extras)
        return rows
    }
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                archiveContainer(proxy: proxy)
                .navigationTitle("Archiv")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                #endif
                .searchable(text: $searchText, prompt: "Sendung suchen...")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button(action: { favoritesOnly.toggle() }) {
                                Label(
                                    favoritesOnly ? "Alle Sendungen" : "Nur Favoriten",
                                    systemImage: favoritesOnly ? "heart.fill" : "heart"
                                )
                            }
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .help("Optionen")
                    }
                }
                .task {
                    if apiClient.shows.isEmpty {
                        await apiClient.fetchShows()
                    }
                }
                .refreshable {
                    await apiClient.fetchShows()
                }
            }
        }
    }

    @ViewBuilder
    private func archiveContainer(proxy: ScrollViewProxy) -> some View {
        if showLetterIndexStrip {
            if usesOverlayLetterIndex {
                archiveList(proxy: proxy)
                    .overlay(alignment: .trailing) {
                        archiveIndexStrip(proxy: proxy)
                            // Avoid visual collision with the list's rounded cards.
                            .padding(.trailing, 8)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                    }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    archiveIndexStrip(proxy: proxy)
                        .frame(maxHeight: .infinity, alignment: .top)
                    Divider()
                    archiveList(proxy: proxy)
                }
            }
        } else {
            archiveList(proxy: proxy)
        }
    }

    private func archiveList(proxy: ScrollViewProxy) -> some View {
        ZStack {
            List {
                ForEach(letterSections, id: \.letter) { section in
                    Section {
                        ForEach(section.shows) { show in
                            showRow(for: show)
                        }
                    } header: {
                        archiveSectionHeader(letter: section.letter)
                            .id(section.letter)
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            .modifier(ArchiveListSectionSpacingModifier())
            #else
            .listStyle(.inset)
            #endif
            .animation(nil, value: hoveredIndexSymbol)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(archiveListDimmedForPlaceholder ? 0.35 : 1)
            .background {
                #if os(macOS)
                ArchiveScrollClampHostViewRepresentable()
                    .allowsHitTesting(false)
                #endif
            }

            if searchText.isEmpty, apiClient.shows.isEmpty {
                Group {
                    if apiClient.lastListRefreshFailedWithoutNetwork {
                        ContentUnavailableView(
                            "Keine Verbindung",
                            systemImage: "wifi.slash",
                            description: Text("Du bist offline oder das Netzwerk ist nicht erreichbar. Archiv-Sendungen können jetzt nicht geladen werden.")
                        )
                    } else {
                        ContentUnavailableView {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Lade Archiv…")
                                    .font(.headline)
                            }
                        } description: {
                            Text("Sendungsliste wird geladen.")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if favoritesOnly, searchText.isEmpty, filteredShows.isEmpty, !apiClient.shows.isEmpty {
                ContentUnavailableView {
                    Label("Keine Favoriten-Sendungen", systemImage: "heart")
                } description: {
                    Text("Du hast noch keine Sendungen als Favorit markiert.")
                } actions: {
                    Button("Alle Sendungen anzeigen") {
                        favoritesOnly = false
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !searchText.isEmpty, filteredShows.isEmpty {
                ContentUnavailableView {
                    Label("Keine Treffer", systemImage: "magnifyingglass")
                } description: {
                    Text("Keine Sendung passt zur Suche.")
                } actions: {
                    Button("Suche löschen") {
                        searchText = ""
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var archiveListDimmedForPlaceholder: Bool {
        if searchText.isEmpty, apiClient.shows.isEmpty { return true }
        if !searchText.isEmpty, filteredShows.isEmpty { return true }
        if favoritesOnly, searchText.isEmpty, filteredShows.isEmpty, !apiClient.shows.isEmpty { return true }
        return false
    }
    
    @ViewBuilder
    private func archiveSectionHeader(letter: String) -> some View {
        let label = ArchiveSectionHelpers.archiveLetterSectionLabel(letter)
        #if os(iOS)
        // iOS List headers should look system-native (no custom boxed background).
        Text(label)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(nil)
        #else
        Text(label)
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(sectionHeaderBackground)
        #endif
    }

    private var sectionHeaderBackground: some View {
        #if os(macOS)
        Color(nsColor: .quaternaryLabelColor).opacity(0.12)
        #else
        Color.secondary.opacity(0.12)
        #endif
    }

    @ViewBuilder
    private var indexStripBackground: some View {
        #if os(iOS)
        // Material reads more native than a flat gray block.
        Rectangle().fill(.thinMaterial)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor).opacity(0.95)
        #else
        Color.secondary.opacity(0.08)
        #endif
    }
    
    /// Schriftgröße des Index (~25 % größer als zuvor 10 pt).
    private var indexFontSize: CGFloat { usesOverlayLetterIndex ? 10.5 : 12.5 }
    
    /// Breite der Index-Spalte (~20 % mehr als zuvor 34 pt).
    private var indexColumnWidth: CGFloat { usesOverlayLetterIndex ? 28 : 41 }
    
    /// Feste Zeilenhöhe, damit Hover-Hintergrund die Index-Spalte nicht neu misst und die Liste nicht mitzieht.
    private var indexRowHeight: CGFloat { usesOverlayLetterIndex ? 16 : 22 }

    private var indexRowSpacing: CGFloat { 2 }

    private var indexVerticalPadding: CGFloat { usesOverlayLetterIndex ? 6 : 4 }
    
    private func archiveIndexStrip(proxy: ScrollViewProxy) -> some View {
        let available = availableSectionIDs
        return VStack(spacing: indexRowSpacing) {
            ForEach(indexStripSymbols, id: \.self) { symbol in
                let isActive = available.contains(symbol)
                let isHovered = hoveredIndexSymbol == symbol
                Button {
                    guard isActive else { return }
                    jumpToSection(symbol, proxy: proxy)
                } label: {
                    Text(ArchiveSectionHelpers.archiveLetterSectionLabel(symbol))
                        .font(.system(size: indexFontSize, weight: .medium, design: .rounded))
                        .frame(minWidth: 28)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                        .frame(height: indexRowHeight)
                        .background(indexHoverBackground(isActive: isActive, isHovered: isHovered))
                }
                .buttonStyle(.plain)
                .foregroundStyle(indexForeground(isActive: isActive, isHovered: isHovered))
                .contentShape(Rectangle())
                .accessibilityLabel(isActive
                    ? "Zu \(ArchiveSectionHelpers.archiveLetterSectionLabel(symbol))"
                    : "\(ArchiveSectionHelpers.archiveLetterSectionLabel(symbol)) nicht verfügbar"
                )
                .accessibilityHint(isActive ? "Springt zu dieser Buchstabengruppe." : "Keine Sendungen in dieser Gruppe.")
                .accessibilityAddTraits(.isButton)
                #if os(macOS)
                .onHover { hovering in
                    hoveredIndexSymbol = hovering ? symbol : nil
                }
                .help(isActive ? "Zu \(ArchiveSectionHelpers.archiveLetterSectionLabel(symbol)) springen" : "Keine Sendung in dieser Gruppe")
                #endif
            }
        }
        .padding(.vertical, indexVerticalPadding)
        .padding(.horizontal, 2)
        .frame(width: indexColumnWidth)
        // Don't stretch to full height: keep background only around actual symbols.
        .background(indexStripBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .simultaneousGesture(indexDragGesture(proxy: proxy))
        // Gleicher Grund wie beim ScrollView: kein Layout-Flattern beim Hover.
        .animation(nil, value: hoveredIndexSymbol)
    }
    
    private func jumpToSection(_ id: String, proxy: ScrollViewProxy, animated: Bool = true) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.45)) {
                    proxy.scrollTo(id, anchor: .top)
                }
            } else {
                proxy.scrollTo(id, anchor: .top)
            }
            
            #if os(macOS)
            // Kurze Verzögerung für das Clamping am Ende des Dokuments, damit es nicht
            // mit der laufenden Animation interferiert.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                ArchiveScrollClampHostView.clampSurroundingScrollViewToContent()
            }
            #endif
        }
    }

    private func indexDragGesture(proxy: ScrollViewProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let symbol = indexSymbol(atY: value.location.y) else { return }
                guard availableSectionIDs.contains(symbol) else { return }
                guard lastIndexDragSymbol != symbol else { return }

                lastIndexDragSymbol = symbol
                hoveredIndexSymbol = symbol
                jumpToSection(symbol, proxy: proxy, animated: false)
            }
            .onEnded { _ in
                lastIndexDragSymbol = nil
                #if os(iOS)
                hoveredIndexSymbol = nil
                #endif
            }
    }

    private func indexSymbol(atY y: CGFloat) -> String? {
        let symbols = indexStripSymbols
        guard !symbols.isEmpty else { return nil }

        let adjustedY = y - indexVerticalPadding
        let rowStride = indexRowHeight + indexRowSpacing
        let rawIndex = Int((adjustedY / rowStride).rounded(.down))
        let clampedIndex = min(max(rawIndex, 0), symbols.count - 1)
        return symbols[clampedIndex]
    }
    
    private func indexForeground(isActive: Bool, isHovered: Bool) -> Color {
        if !isActive {
            return Color.secondary.opacity(0.35)
        }
        if isHovered {
            return Color.accentColor
        }
        return Color.primary
    }
    
    private func indexHoverBackground(isActive: Bool, isHovered: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(indexHoverFill(isActive: isActive, isHovered: isHovered))
    }
    
    private func indexHoverFill(isActive: Bool, isHovered: Bool) -> Color {
        if isHovered {
            return isActive ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14)
        }
        return Color.clear
    }
    
    /// Typo wie bei „Neu im Archiv“ (`BroadcastRow`: `.headline` / `.subheadline`, Herz `.body`).
    @ViewBuilder
    private func showRow(for show: Show) -> some View {
        let isPlaying = playerManager.currentItem?.sendungTitel == show.titel && playerManager.isPlaying
        let accessoryBox: CGFloat = 22

        NavigationLink(destination: BroadcastListView(show: show)) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(show.titel)
                            .font(.headline)
                            .foregroundColor(isPlaying ? .accentColor : .primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                        if apiClient.isFavorite(show: show) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.pink)
                                .font(.body)
                                .frame(width: accessoryBox, height: accessoryBox)
                                .accessibilityLabel("Favorit")
                        }
                    }
                    if !show.untertitel.isEmpty {
                        Text(show.untertitel)
                            .font(.subheadline)
                            .foregroundColor(isPlaying ? .accentColor.opacity(0.8) : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.body)
                        .foregroundColor(.accentColor)
                        .frame(width: accessoryBox, height: accessoryBox)
                }
            }
            // Slightly denser than default while keeping comfortable tap targets.
            .padding(.horizontal, 12)
            .padding(.vertical, 0)
            .contentShape(Rectangle())
            .background(isPlaying ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ArchiveView()
        .environmentObject(APIClient.shared)
        .environmentObject(AudioPlayerManager.shared)
}

#if os(macOS)
/// Hält eine Referenz auf den umgebenden `NSScrollView`, damit nach programmatischem `scrollTo`
/// die Scroll-Position begrenzt werden kann (ohne Elastizität abzuschalten).
private final class ArchiveScrollClampHostView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerScrollView()
    }
    
    override func layout() {
        super.layout()
        registerScrollView()
    }
    
    private func registerScrollView() {
        var v: NSView? = self
        for _ in 0..<80 {
            guard let current = v else { break }
            if let scroll = current as? NSScrollView {
                Self.latestScrollView = scroll
                return
            }
            v = current.superview
        }
    }
    
    private static weak var latestScrollView: NSScrollView?
    
    /// Begrenzt die vertikale Scroll-Position auf den Inhalt (verhindert kurzes Rutschen in den
    /// elastischen Bereich am Ende nach `ScrollViewProxy.scrollTo`).
    static func clampSurroundingScrollViewToContent() {
        guard let scrollView = latestScrollView else { return }
        guard let documentView = scrollView.documentView else { return }
        documentView.layoutSubtreeIfNeeded()
        let clipView = scrollView.contentView
        let docH = documentView.bounds.height
        let visibleH = clipView.bounds.height
        let maxOffset = max(0, docH - visibleH)
        var origin = clipView.bounds.origin
        if clipView.isFlipped {
            if origin.y < 0 { origin.y = 0 }
            else if origin.y > maxOffset { origin.y = maxOffset }
        } else {
            let lowerBound = -maxOffset
            if origin.y > 0 { origin.y = 0 }
            else if origin.y < lowerBound { origin.y = lowerBound }
        }
        if origin != clipView.bounds.origin {
            clipView.setBoundsOrigin(origin)
        }
    }
}

private struct ArchiveScrollClampHostViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ArchiveScrollClampHostView()
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

#if os(iOS)
/// `insetGrouped` can be very airy; keep sections a bit tighter for long lists.
private struct ArchiveListSectionSpacingModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.listSectionSpacing(.compact)
        } else {
            content
        }
    }
}
#endif
