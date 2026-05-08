import SwiftUI
import SwiftData

struct ArchiveNew: View {
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: [
        SortDescriptor(\StoredArchiveItem.datum, order: .reverse),
        SortDescriptor(\StoredArchiveItem.startTime, order: .reverse)
    ]) 
    private var storedItems: [StoredArchiveItem]
    
    @State private var selectedItemForDetail: ArchiveItem?
    @State private var isInspectorPresented = false
    @State private var hidePlayed = false
    @State private var favoritesOnly = false
    
    private var filteredItems: [StoredArchiveItem] {
        var items = storedItems
        if hidePlayed {
            items = items.filter { !apiClient.isPlayed(broadcastID: $0.terminID) }
        }
        if favoritesOnly {
            items = items.filter { apiClient.isFavorite(slug: $0.sendungSlug, title: $0.sendungTitel) }
        }
        return items
    }

    /// Gruppiert nach Kalendertag (neueste Tage zuerst). Als Funktion, damit `body` die gefilterte Liste nur einmal auswertet.
    private func daySections(from items: [StoredArchiveItem]) -> [(dayStart: Date, header: String, items: [StoredArchiveItem])] {
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
        let sections = daySections(from: filtered)
        ZStack {
            List {
                ForEach(sections, id: \.dayStart) { section in
                    Section(header: Text(section.header)) {
                        ForEach(section.items) { storedItem in
                            let item = storedItem.toArchiveItem()
                            BroadcastRow(
                                item: item,
                                onFavoriteTap: apiClient.isLoggedIn
                                    ? { Task { await apiClient.toggleFavoriteBroadcast(slug: item.sendungSlug, displayTitle: item.sendungTitel) } }
                                    : nil,
                                selectedItemForDetail: $selectedItemForDetail,
                                isInspectorPresented: $isInspectorPresented
                            )
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
        .task {
            await apiClient.fetchArchive()
        }
    }
}
