import SwiftUI
import SwiftData

struct ArchiveNew: View {
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var activePlayback: ActivePlaybackStore
    @Environment(\.modelContext) private var modelContext
    #if os(iOS)
    @EnvironmentObject private var downloadManager: IOSDownloadManager
    #endif

    @Query(sort: [
        SortDescriptor(\StoredArchiveItem.datum, order: .reverse),
        SortDescriptor(\StoredArchiveItem.startTime, order: .reverse)
    ]) 
    private var storedItems: [StoredArchiveItem]
    
    @State private var selectedItemForDetail: ArchiveItem?
    @State private var isInspectorPresented = false
    @State private var hidePlayed = false
    @State private var favoritesOnly = false

    /// Memo-Cache für die Tages-Gruppierung. Wird nur neu berechnet, wenn sich die gefilterten
    /// Items ändern — nicht bei jedem `body`-Durchlauf. Schützt davor, dass unabhängige
    /// `APIClient`-Updates (z. B. der Hörverlauf-Poll während der Wiedergabe) die Liste neu gruppieren.
    ///
    /// `StoredArchiveItem` ist eine SwiftData-`@Model`-Klasse (nicht `Equatable`), daher basiert die
    /// Signatur auf genau den Feldern, die für Gruppierung/Sortierung relevant sind.
    @State private var daySectionsCache: (signature: DaySectionsSignature, sections: [(dayStart: Date, header: String, items: [StoredArchiveItem])])?

    private struct DaySectionsSignature: Equatable {
        struct Row: Equatable {
            let terminID: Int
            let startTime: String
            let day: TimeInterval
        }
        let rows: [Row]

        init(_ items: [StoredArchiveItem]) {
            let cal = Calendar.current
            self.rows = items.map {
                Row(terminID: $0.terminID, startTime: $0.startTime, day: cal.startOfDay(for: $0.broadcastDate).timeIntervalSince1970)
            }
        }
    }

    private var filteredItems: [StoredArchiveItem] {
        var items = storedItems
        if hidePlayed {
            let pinnedTerminID: Int? = activePlayback.isActivePlaying ? nil : activePlayback.activeTerminID
            items = items.filter { stored in
                !apiClient.isPlayed(broadcastID: stored.terminID) || stored.terminID == pinnedTerminID
            }
        }
        if favoritesOnly {
            items = items.filter { apiClient.isFavorite(slug: $0.sendungSlug, title: $0.sendungTitel) }
        }
        return items
    }

    /// Befüllt `daySectionsCache` außerhalb von `body` (in `.task`/`.onChange`), damit kein
    /// State während des View-Updates mutiert wird.
    private func refreshDaySections() {
        let items = filteredItems
        let signature = DaySectionsSignature(items)
        if daySectionsCache?.signature != signature {
            daySectionsCache = (signature, computeDaySections(from: items))
        }
    }

    private func computeDaySections(from items: [StoredArchiveItem]) -> [(dayStart: Date, header: String, items: [StoredArchiveItem])] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: items) { cal.startOfDay(for: $0.broadcastDate) }
        let days = byDay.keys.sorted(by: >)
        return days.map { day in
            let rowItems = (byDay[day] ?? []).sorted { lhs, rhs in
                if lhs.startTime != rhs.startTime {
                    return lhs.startTime > rhs.startTime
                }
                return lhs.terminID > rhs.terminID
            }
            let header = ArchiveSectionHelpers.newArchiveDaySectionHeader(for: day)
            return (dayStart: day, header: header, items: rowItems)
        }
    }
    
    private var emptyFilterUnavailable: (title: String, systemImage: String, description: String) {
        if hidePlayed && favoritesOnly {
            let anyFavoriteInList = storedItems.contains { apiClient.isFavorite(slug: $0.sendungSlug, title: $0.sendungTitel) }
            if !anyFavoriteInList {
                return (
                    title: "Keine Favoriten-Sendungen",
                    systemImage: "heart",
                    description: "In dieser Liste sind keine Sendungen von als Favorit markierten Sendereihen."
                )
            }
            return (
                title: "Keine passenden Sendungen",
                systemImage: "checkmark.circle",
                description: "Keine ungehörten Sendungen von Favoriten-Sendungen in dieser Liste."
            )
        }
        if hidePlayed {
            return (
                title: "Alle Sendungen gehört",
                systemImage: "checkmark.circle",
                description: "Du hast alle aktuellen Sendungen in dieser Liste bereits gehört."
            )
        }
        if favoritesOnly {
            return (
                title: "Keine Favoriten-Sendungen",
                systemImage: "heart",
                description: "In dieser Liste sind keine Sendungen von als Favorit markierten Sendereihen."
            )
        }
        preconditionFailure("emptyFilterUnavailable without active filters")
    }
    
    var body: some View {
        let filtered = filteredItems
        // Rein lesend: Cache nutzen, sonst einmalig rein berechnen (KEIN State-Write in `body`).
        let sections = daySectionsCache?.signature == DaySectionsSignature(filtered)
            ? daySectionsCache!.sections
            : computeDaySections(from: filtered)
        ZStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(sections, id: \.dayStart) { section in
                        Section(header: Text(section.header)) {
                            let rows = section.items
                            ForEach(Array(rows.enumerated()), id: \.element.terminID) { idx, storedItem in
                                let isFirst = idx == 0
                                let isLast = idx == rows.count - 1
                                let top: CGFloat = isFirst ? 12 : 4
                                let bottom: CGFloat = isLast ? 12 : 4
                                let item = storedItem.toArchiveItem()

                                BroadcastRow(
                                    item: item,
                                    onFavoriteTap: apiClient.isLoggedIn
                                        ? { Task { await apiClient.toggleFavoriteBroadcast(slug: item.sendungSlug, displayTitle: item.sendungTitel) } }
                                        : nil,
                                    selectedItemForDetail: $selectedItemForDetail,
                                    isInspectorPresented: $isInspectorPresented
                                )
                                // Erste/letzte echte Row schaffen die Section-Luft; keine extra
                                // Spacer-Zeile, da `List` sonst eine Mindesthöhe erzwingt.
                                .listRowInsets(EdgeInsets(top: top, leading: 10, bottom: bottom, trailing: 12))
                                .id(storedItem.terminID)
                            }
                            }
                        }
                    }
                }
                .refreshable {
                    await apiClient.fetchArchive()
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
                .opacity(filtered.isEmpty ? 0 : 1)
                .task {
                    await apiClient.fetchArchive()
                    refreshDaySections()
                }
                .onChange(of: storedItems) { _, _ in
                    // Kein Scroll-Anker-Restore mehr.
                    refreshDaySections()
                }
                .onChange(of: filteredItems) { _, _ in
                    refreshDaySections()
                }
            
            if filtered.isEmpty && !storedItems.isEmpty {
                let empty = emptyFilterUnavailable
                ContentUnavailableView {
                    Label(empty.title, systemImage: empty.systemImage)
                } description: {
                    Text(empty.description)
                } actions: {
                    Button("Filter zurücksetzen") {
                        hidePlayed = false
                        favoritesOnly = false
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .broadcastInspector(isPresented: $isInspectorPresented, selectedItem: $selectedItemForDetail)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: { hidePlayed.toggle() }) {
                        Label(
                            hidePlayed ? "Gehörte einblenden" : "Gehörte ausblenden",
                            systemImage: hidePlayed ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
                        )
                    }

                    Button(action: { favoritesOnly.toggle() }) {
                        Label(
                            favoritesOnly ? "Alle Sendungen" : "Nur Favoriten-Sendungen",
                            systemImage: favoritesOnly ? "heart.fill" : "heart"
                        )
                    }

                    #if os(macOS)
                    Button(action: { isInspectorPresented.toggle() }) {
                        Label(isInspectorPresented ? "Details ausblenden" : "Details anzeigen", systemImage: "sidebar.right")
                    }
                    #endif
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("Optionen")
            }
        }
        .onDisappear {
            // Kein Scroll-Anker-Restore mehr: Scroll-Position wird nicht mehr gespeichert.
        }
    }
}
