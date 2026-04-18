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
    
    /// Gruppiert nach Kalendertag (neueste Tage zuerst).
    private var daySections: [(dayStart: Date, header: String, items: [StoredArchiveItem])] {
        let cal = Calendar.current
        let items = filteredItems
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
    
    var body: some View {
        ZStack {
            List {
                ForEach(daySections, id: \.dayStart) { section in
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
            .opacity(filteredItems.isEmpty ? 0 : 1)
            
            if filteredItems.isEmpty && !storedItems.isEmpty {
                let empty = emptyFilterUnavailable
                ContentUnavailableView(
                    empty.title,
                    systemImage: empty.systemImage,
                    description: Text(empty.description)
                )
            }
        }
        .broadcastInspector(isPresented: $isInspectorPresented, selectedItem: $selectedItemForDetail)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Button(action: {
                        hidePlayed.toggle()
                    }) {
                        Label(hidePlayed ? "Alle anzeigen" : "Gehörte ausblenden", 
                              systemImage: hidePlayed ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .help(hidePlayed ? "Alle Sendungen anzeigen" : "Gehörte Sendungen ausblenden")

                    Button(action: {
                        favoritesOnly.toggle()
                    }) {
                        Label(
                            favoritesOnly ? "Alle Sendungen" : "Nur Favoriten-Sendungen",
                            systemImage: favoritesOnly ? "heart.fill" : "heart"
                        )
                    }
                    .help(favoritesOnly ? "Alle Sendungen anzeigen" : "Nur Sendungen von favorisierten Sendereihen")

                    #if os(macOS)
                    Button(action: {
                        isInspectorPresented.toggle()
                    }) {
                        Label("Details anzeigen", systemImage: "sidebar.right")
                    }
                    .help("Info ein-/ausblenden")
                    #endif
                }
            }
        }
        .task {
            await apiClient.fetchArchive(modelContext: modelContext)
        }
    }
}
