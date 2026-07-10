import SwiftUI
import SwiftData

struct ArchiveNew: View {
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var activePlayback: ActivePlaybackStore
    @EnvironmentObject private var restorationStore: AppRestorationStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: [
        SortDescriptor(\StoredArchiveItem.datum, order: .reverse),
        SortDescriptor(\StoredArchiveItem.startTime, order: .reverse)
    ]) 
    private var storedItems: [StoredArchiveItem]
    
    @State private var selectedItemForDetail: ArchiveItem?
    @State private var isInspectorPresented = false
    @State private var hidePlayed = false
    @State private var favoritesOnly = false
    /// In-View-Tracking der zuletzt sichtbaren Termin-ID. Wir schreiben sie nicht bei jedem Scroll-Event nach
    /// `UserDefaults`, sondern nur, wenn die View verschwindet oder die App in den Hintergrund geht.
    @State private var lastVisibleTerminID: Int?
    @State private var didRestoreScrollAnchor: Bool = false
    
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
                                .onAppear {
                                    // Letzter „angekommener“ Termin = grobe Schätzung der aktuellen Scroll-Position.
                                    // Reine View-State-Aktualisierung — kein UserDefaults-Write während des Scrollens.
                                    lastVisibleTerminID = storedItem.terminID
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
                    restoreScrollAnchorIfPossible(proxy: proxy, items: filtered)
                }
                .onChange(of: storedItems) { _, _ in
                    // Erst nach erstem Datenladen kann ein gespeicherter Anker greifen.
                    restoreScrollAnchorIfPossible(proxy: proxy, items: filteredItems)
                }
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
            // Beim Verlassen der View den groben Scroll-Anker einmalig persistieren — Schreiben passiert nicht im Scroll-Pfad.
            persistScrollAnchorIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Bevor die App in den Hintergrund geht (oder dazwischen pausiert), den Anker einmalig nachziehen.
            if newPhase == .background || newPhase == .inactive {
                persistScrollAnchorIfNeeded()
            }
        }
    }

    private func persistScrollAnchorIfNeeded() {
        guard let id = lastVisibleTerminID else { return }
        restorationStore.setArchiveNewScrollAnchor(terminID: id)
    }

    private func restoreScrollAnchorIfPossible(proxy: ScrollViewProxy, items: [StoredArchiveItem]) {
        let sessionKey = "ArchiveNew.scrollAnchor"
        guard !didRestoreScrollAnchor, restorationStore.shouldRestore(key: sessionKey) else { return }
        guard let id = restorationStore.validScrollAnchors.archiveNewTerminID else {
            didRestoreScrollAnchor = true
            restorationStore.markRestored(key: sessionKey)
            return
        }
        guard items.contains(where: { $0.terminID == id }) else { return }
        didRestoreScrollAnchor = true
        restorationStore.markRestored(key: sessionKey)
        // `scrollTo` ohne Animation, damit der Restore nicht als sichtbares Springen erscheint.
        proxy.scrollTo(id, anchor: .top)
    }
}
