import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct ArchiveView: View {
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var hoveredIndexSymbol: String?
    
    private var filteredShows: [Show] {
        if searchText.isEmpty {
            return apiClient.shows
        } else {
            return apiClient.shows.filter { 
                $0.titel.localizedCaseInsensitiveContains(searchText) || 
                $0.untertitel.localizedCaseInsensitiveContains(searchText)
            }
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
                HStack(alignment: .top, spacing: 0) {
                    archiveIndexStrip(proxy: proxy)
                    
                    Divider()
                    
                    // Keine List: NSTableView lädt Sektionen lazy — scrollTo springt dann nur schrittweise.
                    // VStack über alle Sektionen legt alle Sprungmarken sofort ins Layout.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(letterSections, id: \.letter) { section in
                                archiveLetterSectionBlock(section: section)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            #if os(macOS)
                            ArchiveScrollClampHostViewRepresentable()
                                .allowsHitTesting(false)
                            #endif
                        }
                    }
                    // Hover im Index darf keine implizite Layout-Animation auslösen (sonst „wandert“ die Liste).
                    .animation(nil, value: hoveredIndexSymbol)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .navigationTitle("Archiv")
                .searchable(text: $searchText, prompt: "Sendung suchen...")
                .task {
                    if apiClient.shows.isEmpty {
                        await apiClient.fetchShows(modelContext: modelContext)
                    }
                }
                .refreshable {
                    await apiClient.fetchShows(modelContext: modelContext)
                }
            }
        }
    }
    
    @ViewBuilder
    private func archiveLetterSectionBlock(section: (letter: String, shows: [Show])) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            archiveSectionHeader(letter: section.letter)
                .id(section.letter)
            
            VStack(alignment: .leading, spacing: 0) {
                ForEach(section.shows) { show in
                    showRow(for: show)
                    Divider()
                        .padding(.leading, 8)
                }
            }
        }
    }
    
    private func archiveSectionHeader(letter: String) -> some View {
        Text(ArchiveSectionHelpers.archiveLetterSectionLabel(letter))
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.12))
    }
    
    /// Schriftgröße des Index (~25 % größer als zuvor 10 pt).
    private var indexFontSize: CGFloat { 12.5 }
    
    /// Breite der Index-Spalte (~20 % mehr als zuvor 34 pt).
    private var indexColumnWidth: CGFloat { 41 }
    
    /// Feste Zeilenhöhe, damit Hover-Hintergrund die Index-Spalte nicht neu misst und die Liste nicht mitzieht.
    private var indexRowHeight: CGFloat { 22 }
    
    private func archiveIndexStrip(proxy: ScrollViewProxy) -> some View {
        let available = availableSectionIDs
        return VStack(spacing: 2) {
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
                .onHover { hovering in
                    hoveredIndexSymbol = hovering ? symbol : nil
                }
                .help(isActive ? "Zu \(ArchiveSectionHelpers.archiveLetterSectionLabel(symbol)) springen" : "Keine Sendung in dieser Gruppe")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .frame(width: indexColumnWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.95))
        // Gleicher Grund wie beim ScrollView: kein Layout-Flattern beim Hover.
        .animation(nil, value: hoveredIndexSymbol)
    }
    
    private func jumpToSection(_ id: String, proxy: ScrollViewProxy) {
        let animation = Animation.easeInOut(duration: 0.45)
        
        DispatchQueue.main.async {
            // Mit VStack (statt LazyVStack) sind alle Höhen sofort bekannt.
            // Ein einziger animierter Pass reicht nun aus.
            withAnimation(animation) {
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
    
    @ViewBuilder
    private func showRow(for show: Show) -> some View {
        let isPlaying = playerManager.currentItem?.sendungTitel == show.titel && playerManager.isPlaying
        
        NavigationLink(destination: BroadcastListView(show: show)) {
            HStack {
                VStack(alignment: .leading) {
                    HStack(spacing: 4) {
                        if apiClient.isFavorite(show: show) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        Text(show.titel)
                            .font(.headline)
                            .foregroundColor(isPlaying ? .accentColor : .primary)
                    }
                    if !show.untertitel.isEmpty {
                        Text(show.untertitel)
                            .font(.subheadline)
                            .foregroundColor(isPlaying ? .accentColor.opacity(0.8) : .secondary)
                    }
                }
                Spacer()
                
                if isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
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
