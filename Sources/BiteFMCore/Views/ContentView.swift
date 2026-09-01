import SwiftUI
#if os(iOS)
import UIKit
#endif

public struct ContentView: View {
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var restorationStore: AppRestorationStore
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        Group {
            if apiClient.isLoggedIn {
                if apiClient.didFinishInitialBootstrap {
                    LoggedInRootView()
                } else {
                    InitialLoadingView()
                }
            } else {
                LoginView()
                    .task {
                        await apiClient.autoLogin()
                    }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                #if os(iOS)
                // Defer the resume to the next run loop so scene activation can settle first.
                Task { @MainActor in
                    await Task.yield()
                    apiClient.resumeDeferredPollingIfConfigured()
                    await IOSDownloadManager.shared.runForegroundMaintenance()
                }
                #endif
            case .background:
                #if os(iOS)
                apiClient.pauseDeferredPolling()
                #endif
                // Restoration-Snapshot beim Wechsel in den Hintergrund sofort persistieren — auf iOS, weil die App
                // dort jederzeit terminiert werden kann; auf macOS schadet ein Flush nicht (Quit signalisiert keinen
                // gesonderten scenePhase-Wechsel zuverlässig vor dem Beenden).
                restorationStore.flushNow()
            case .inactive:
                // iOS: Home-Swipe / App Switcher → vor möglichem Termination noch einmal hart speichern.
                restorationStore.flushNow()
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Logged-in shell

private struct InitialLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Daten werden geladen …")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LoggedInRootView: View {
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @EnvironmentObject private var restorationStore: AppRestorationStore
    #if os(iOS)
    @EnvironmentObject private var downloadManager: IOSDownloadManager
    #endif

    enum SidebarItem: Hashable {
        case live
        case archiveNew
        case archive
        #if os(iOS)
        case downloads
        #endif
        case favoriteEpisodes
        case favoriteTracks
        case show(Show)
    }

    enum MainTab: Hashable {
        case live
        case archiveNew
        case archive
        case favorites
        #if os(iOS)
        case downloads
        #endif
    }

    @State private var selection: SidebarItem? = .live
    @State private var isFavoritesExpanded: Bool = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedTab: MainTab = .live
    @State private var logoutAlertPresented: Bool = false
    @State private var isNowPlayingExpanded: Bool = false
    @State private var didApplyRestoredRoot: Bool = false
    @State private var didRestorePlaybackSnapshot: Bool = false
    /// Eine Sidebar-`show(...)`-Wiederherstellung kann beim ersten `task` noch nicht greifen, wenn `apiClient.shows`
    /// gerade nachgeladen wird. Wir versuchen es einmalig, sobald die Sendungsliste gefüllt ist.
    @State private var pendingShowRestoreSlug: String?
    /// Tiefe Navigation des iPhone-Favoriten-Tabs. Nur stabile, semantische Routen — keine View-Hierarchie.
    @State private var favoritesPath: [AppRestorationState.DeepRoute] = []
    @State private var didApplyRestoredFavoritesPath: Bool = false
    #if os(iOS)
    @State private var didApplyOfflineLaunchTab = false
    #endif

    private var useCompactRoot: Bool {
        #if os(iOS)
        // Die Root-Shell darf beim Start nicht zwischen Tab- und Split-Layout umspringen.
        // `horizontalSizeClass` ist auf iOS beim ersten Render oft noch unstabil und kann dadurch
        // LiveView/Navigation mehrfach mounten. Für die Root-Entscheidung deshalb nur das Gerätetyp-Signal nutzen.
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if useCompactRoot {
                    compactTabShell
                } else {
                    splitShell
                    PlayerBarView()
                }
            }
        }
        .task {
            applyRestoredRootIfNeeded()
            restorePlaybackSnapshotIfNeeded()
            applyRestoredFavoritesPathIfNeeded(shows: apiClient.shows)
            #if os(iOS)
            await applyOfflineLaunchOverrideIfNeeded()
            #endif
        }
        .onChange(of: apiClient.shows) { _, newShows in
            // Sidebar-`show(...)`-Eintrag kann erst zugewiesen werden, sobald die Sendungsliste verfügbar ist.
            applyRestoredShowSelectionIfPending(shows: newShows)
            applyRestoredFavoritesPathIfNeeded(shows: newShows)
        }
        .onChange(of: selectedTab) { _, newTab in
            persistSelectedTab(newTab)
        }
        .onChange(of: selection) { _, newSelection in
            persistSelectedSidebarItem(newSelection)
        }
        .onChange(of: favoritesPath) { _, newPath in
            persistFavoritesPath(newPath)
        }
        .alert("Abmelden?", isPresented: $logoutAlertPresented) {
            Button("Abbrechen", role: .cancel) {}
            Button("Abmelden", role: .destructive) {
                apiClient.logout()
            }
        } message: {
            Text("Wenn Sie sich abmelden, werden alle Daten (gespeicherte Sendungen 'Neu im Archiv') gelöscht. Diese sind nicht wiederherzustellen.")
        }
        .onReceive(NotificationCenter.default.publisher(for: APIClient.requestLogoutConfirmationNotification)) { _ in
            logoutAlertPresented = true
        }
        .onChange(of: playerManager.currentItem?.id) { _, _ in
            if playerManager.currentItem == nil && !playerManager.isLive {
                isNowPlayingExpanded = false
            }
        }
        .onChange(of: playerManager.isLive) { _, newValue in
            if playerManager.currentItem == nil && !newValue {
                isNowPlayingExpanded = false
            }
        }
        #if os(iOS)
        .alert("Download-Speicher", isPresented: Binding(
            get: { downloadManager.budgetPrompt != nil },
            // Ein Alert schreibt beim Schließen noch einmal `false`. Die Aktionen selbst
            // verwalten den Zustand; sonst kann dieser späte Rückruf einen direkt danach
            // gesetzten Folge-Dialog wieder löschen und die Download-Queue erneut auslösen.
            set: { _ in }
        )) {
            if let deletionCount = downloadManager.budgetPrompt?.deletionCount,
               deletionCount > 0 {
                Button(deletionCount == 1 ? "Ältesten Download löschen" : "\(deletionCount) älteste Downloads löschen") {
                    Task { await downloadManager.confirmDeleteOldestForBudgetAndRetry() }
                }
            }
            if let nextLimit = downloadManager.budgetPrompt?.nextStorageLimitLabel {
                Button("Limit auf \(nextLimit) erhöhen") {
                    Task { await downloadManager.increaseStorageLimitAndRetry() }
                }
                .disabled(downloadManager.budgetPrompt?.canIncreaseStorageLimit != true)
            }
            Button("Abbrechen", role: .cancel) {
                downloadManager.dismissBudgetPrompt()
            }
        } message: {
            VStack(alignment: .leading, spacing: 4) {
                Text(downloadManager.budgetPrompt?.message ?? "")
                if let nextLimit = downloadManager.budgetPrompt?.nextStorageLimitLabel {
                    if downloadManager.budgetPrompt?.canIncreaseStorageLimit == true {
                        Text("Alternativ: Limit auf \(nextLimit) erhöhen.")
                    } else {
                        Text("Für \(nextLimit) ist auf dem iPhone nicht genug freier Speicher verfügbar.")
                    }
                }
            }
        }
        .alert("Speicher", isPresented: Binding(
            get: { downloadManager.deviceSpaceError != nil },
            set: { if !$0 { downloadManager.deviceSpaceError = nil } }
        )) {
            Button("OK", role: .cancel) {
                downloadManager.deviceSpaceError = nil
            }
        } message: {
            Text(downloadManager.deviceSpaceError ?? "")
        }
        // iPhone: Now Playing is an animated overlay (see above).
        // iPad: keep the default sheet presentation.
        .sheet(isPresented: Binding(
            get: { isNowPlayingExpanded && !useCompactRoot },
            set: { isNowPlayingExpanded = $0 }
        )) {
            ExpandedNowPlayingView()
                .environmentObject(apiClient)
                .environmentObject(playerManager)
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: Binding(
            get: { isNowPlayingExpanded && useCompactRoot },
            set: { isNowPlayingExpanded = $0 }
        )) {
            ExpandedNowPlayingView(allowsSwipeToDismiss: true)
                .environmentObject(apiClient)
                .environmentObject(playerManager)
        }
        #endif
    }

    /// Only mount the active tab to keep root-level subscribers lightweight on iPhone.
    /// Tab-Leiste liegt in einer **eigenen** `View`, die nur `AudioPlayerManager` beobachtet — nicht `IOSDownloadManager`,
    /// damit Häufige Download-Fortschritts-Updates die Miniplayer-Taps/`tabViewBottomAccessory` nicht lahmlegen.
    #if os(iOS)
    @ViewBuilder
    private var compactTabShell: some View {
        if #available(iOS 26.1, *) {
            IPhoneTabShellWithBottomAccessory(
                selectedTab: $selectedTab,
                isNowPlayingExpanded: $isNowPlayingExpanded,
                favoritesPath: $favoritesPath
            )
        } else {
            IPhoneTabShellLegacyInset(
                selectedTab: $selectedTab,
                isNowPlayingExpanded: $isNowPlayingExpanded,
                favoritesPath: $favoritesPath
            )
        }
    }

    /// iOS 26.1+: System-Tab-Bottom-Accessory + Tab-Leisten-Minimizer.
    @available(iOS 26.1, *)
    private struct IPhoneTabShellWithBottomAccessory: View {
        @EnvironmentObject private var playerManager: AudioPlayerManager
        @Binding var selectedTab: MainTab
        @Binding var isNowPlayingExpanded: Bool
        @Binding var favoritesPath: [AppRestorationState.DeepRoute]

        var body: some View {
            let miniActive = playerManager.currentItem != nil || playerManager.isLive
            TabView(selection: $selectedTab) {
                Tab("Live", systemImage: "radio", value: MainTab.live) {
                    NavigationStack {
                        LiveView()
                        .navigationTitle("Live")
                        .navigationBarTitleDisplayMode(.large)
                    }
                }

                Tab("Neu", systemImage: "clock", value: MainTab.archiveNew) {
                    NavigationStack {
                        ArchiveNew()
                        .navigationTitle("Neu im Archiv")
                        .navigationBarTitleDisplayMode(.large)
                    }
                }

                Tab("Archiv", systemImage: "archivebox", value: MainTab.archive) {
                    NavigationStack {
                        ArchiveView()
                    }
                }

                Tab("Favoriten", systemImage: "heart.fill", value: MainTab.favorites) {
                    NavigationStack(path: $favoritesPath) {
                        FavoritesHubView()
                        .navigationTitle("Favoriten")
                        .navigationBarTitleDisplayMode(.large)
                        .navigationDestination(for: AppRestorationState.DeepRoute.self) { route in
                            FavoritesRouteDestination(route: route)
                        }
                    }
                }

                Tab("Downloads", systemImage: "arrow.down.circle", value: MainTab.downloads) {
                    NavigationStack {
                        DownloadsView()
                    }
                }
            }
            .tabBarMinimizeBehavior(.automatic)
            .tabViewBottomAccessory(isEnabled: miniActive) {
                MiniPlayerBarView(
                    onExpand: { expandNowPlaying() },
                    chrome: .tabAccessory
                )
                .environmentObject(playerManager)
            }
        }

        private func expandNowPlaying() {
            isNowPlayingExpanded = true
        }
    }

    /// iOS 17–26.0: `safeAreaInset` + klassische `tabItem`-Tabs.
    private struct IPhoneTabShellLegacyInset: View {
        @EnvironmentObject private var playerManager: AudioPlayerManager
        @Binding var selectedTab: MainTab
        @Binding var isNowPlayingExpanded: Bool
        @Binding var favoritesPath: [AppRestorationState.DeepRoute]

        var body: some View {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    LiveView()
                    .navigationTitle("Live")
                    .navigationBarTitleDisplayMode(.large)
                }
                .tabItem { Label("Live", systemImage: "radio") }
                .tag(MainTab.live)

                NavigationStack {
                    ArchiveNew()
                    .navigationTitle("Neu im Archiv")
                    .navigationBarTitleDisplayMode(.large)
                }
                .tabItem { Label("Neu", systemImage: "clock") }
                .tag(MainTab.archiveNew)

                NavigationStack {
                    ArchiveView()
                }
                .tabItem { Label("Archiv", systemImage: "archivebox") }
                .tag(MainTab.archive)

                NavigationStack(path: $favoritesPath) {
                    FavoritesHubView()
                    .navigationTitle("Favoriten")
                    .navigationBarTitleDisplayMode(.large)
                    .navigationDestination(for: AppRestorationState.DeepRoute.self) { route in
                        FavoritesRouteDestination(route: route)
                    }
                }
                .tabItem { Label("Favoriten", systemImage: "heart.fill") }
                .tag(MainTab.favorites)

                NavigationStack {
                    DownloadsView()
                }
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                .tag(MainTab.downloads)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if playerManager.currentItem != nil || playerManager.isLive {
                    MiniPlayerBarView(
                        onExpand: { expandNowPlaying() },
                        chrome: .safeAreaInsetRow
                    )
                }
            }
        }

        private func expandNowPlaying() {
            isNowPlayingExpanded = true
        }
    }
    #else
    private var compactTabShell: some View {
        EmptyView()
    }
    #endif

    // MARK: - Restoration helpers

    private func applyRestoredRootIfNeeded() {
        guard !didApplyRestoredRoot else { return }
        didApplyRestoredRoot = true
        guard let root = restorationStore.validSelectedRoot else { return }

        if useCompactRoot {
            if let tab = Self.mainTab(from: root) {
                selectedTab = tab
            }
        } else {
            if let item = Self.sidebarItem(from: root, shows: apiClient.shows) {
                selection = item
            } else if case .show(let slug, _) = root {
                // Sendungsliste noch nicht geladen — Auswahl per `onChange(of: apiClient.shows)` nachreichen.
                pendingShowRestoreSlug = slug
            }
        }
    }

    private func applyRestoredShowSelectionIfPending(shows: [Show]) {
        guard !useCompactRoot else { return }
        guard let slug = pendingShowRestoreSlug else { return }
        guard let match = shows.first(where: { $0.slug == slug }) else { return }
        // Nur einmalig — wenn der Nutzer inzwischen selbst etwas anderes gewählt hat, respektieren wir das.
        pendingShowRestoreSlug = nil
        if selection == .live || selection == nil {
            selection = .show(match)
        }
    }

    private func restorePlaybackSnapshotIfNeeded() {
        guard !didRestorePlaybackSnapshot else { return }
        didRestorePlaybackSnapshot = true
        playerManager.restoreLastSessionSnapshotIfNeeded()
    }

    #if os(iOS)
    private func applyOfflineLaunchOverrideIfNeeded() async {
        guard !didApplyOfflineLaunchTab else { return }
        didApplyOfflineLaunchTab = true
        let online = await NetworkPathProbe.isPathSatisfied()
        guard !online else { return }
        // Offline gewinnt gegen die wiederhergestellte Auswahl: Downloads sind dann der einzig sinnvolle Einstieg.
        if useCompactRoot {
            selectedTab = .downloads
        } else {
            selection = .downloads
        }
    }
    #endif

    private func applyRestoredFavoritesPathIfNeeded(shows: [Show]) {
        guard !didApplyRestoredFavoritesPath else { return }
        // Auf Mac/iPad gibt es keinen iPhone-Tab-`NavigationStack`; in dem Fall überspringen wir die Wiederherstellung,
        // ohne den Snapshot zu verwerfen — beim nächsten iPhone-Start kann er weiterhin greifen.
        guard useCompactRoot else { return }

        let raw = restorationStore.validNavigationRoutes.favorites
        let sanitized = sanitizeFavoritesRoutes(raw, shows: shows)

        // Wenn der Snapshot ungültig wurde (Sendung nicht mehr da) und sich dadurch die Liste verkürzt, sollten wir ihn auch
        // im Speicher angleichen, damit kein veraltetes Ziel beim nächsten Start erneut probiert wird.
        if sanitized.count != raw.count {
            restorationStore.setFavoritesPath(sanitized)
        }

        didApplyRestoredFavoritesPath = true
        guard !sanitized.isEmpty else { return }

        // Pfad nur anwenden, wenn der Nutzer den Tab nicht inzwischen selbst weiternavigiert hat.
        if favoritesPath.isEmpty {
            favoritesPath = sanitized
        }
    }

    private func sanitizeFavoritesRoutes(_ routes: [AppRestorationState.DeepRoute], shows: [Show]) -> [AppRestorationState.DeepRoute] {
        // Wir entfernen `show(...)`-Routen, deren Sendung wir aktuell nicht (mehr) kennen — entweder weil sie nicht mehr
        // existiert oder weil die Sendungsliste schlicht noch nicht geladen ist; im zweiten Fall versucht es ein erneutes
        // `apply` nach dem nächsten `apiClient.shows`-Update.
        guard !shows.isEmpty else { return [] }
        return routes.filter { route in
            switch route {
            case .favoriteEpisodes, .favoriteTracks:
                return true
            case .show(let slug, _, let id):
                if let id, shows.contains(where: { $0.id == id }) { return true }
                return shows.contains(where: { $0.slug == slug })
            }
        }
    }

    private func persistFavoritesPath(_ path: [AppRestorationState.DeepRoute]) {
        // Wir akzeptieren auch das vorgezogene Schreiben vor `didApplyRestoredFavoritesPath`,
        // damit eine vom System wiederhergestellte Tab-Auswahl nicht den gespeicherten Pfad sofort zurücksetzt:
        // erst nach erstem Restore wird `favoritesPath` verändert.
        restorationStore.setFavoritesPath(path)
    }

    private func persistSelectedTab(_ tab: MainTab) {
        guard didApplyRestoredRoot else { return }
        restorationStore.setSelectedRoot(Self.selectedRoot(forTab: tab))
    }

    private func persistSelectedSidebarItem(_ item: SidebarItem?) {
        guard didApplyRestoredRoot else { return }
        guard let item, let root = Self.selectedRoot(forSidebar: item) else { return }
        restorationStore.setSelectedRoot(root)
    }

    private static func selectedRoot(forTab tab: MainTab) -> AppRestorationState.SelectedRoot {
        switch tab {
        case .live: return .live
        case .archiveNew: return .archiveNew
        case .archive: return .archive
        case .favorites: return .favoritesHub
        #if os(iOS)
        case .downloads: return .downloads
        #endif
        }
    }

    private static func mainTab(from root: AppRestorationState.SelectedRoot) -> MainTab? {
        switch root {
        case .live: return .live
        case .archiveNew: return .archiveNew
        case .archive: return .archive
        case .favoritesHub, .favoriteEpisodes, .favoriteTracks, .show: return .favorites
        case .downloads:
            #if os(iOS)
            return .downloads
            #else
            return nil
            #endif
        }
    }

    private static func selectedRoot(forSidebar item: SidebarItem) -> AppRestorationState.SelectedRoot? {
        switch item {
        case .live: return .live
        case .archiveNew: return .archiveNew
        case .archive: return .archive
        case .favoriteEpisodes: return .favoriteEpisodes
        case .favoriteTracks: return .favoriteTracks
        case .show(let show): return .show(slug: show.slug, title: show.titel)
        #if os(iOS)
        case .downloads: return .downloads
        #endif
        }
    }

    private static func sidebarItem(from root: AppRestorationState.SelectedRoot, shows: [Show]) -> SidebarItem? {
        switch root {
        case .live: return .live
        case .archiveNew: return .archiveNew
        case .archive: return .archive
        case .favoriteEpisodes: return .favoriteEpisodes
        case .favoriteTracks: return .favoriteTracks
        case .favoritesHub: return nil
        case .downloads:
            #if os(iOS)
            return .downloads
            #else
            return nil
            #endif
        case .show(let slug, _):
            if let match = shows.first(where: { $0.slug == slug }) { return .show(match) }
            return nil
        }
    }

    private var splitShell: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                List(selection: $selection) {
                    NavigationLink(value: SidebarItem.live) {
                        Label("Live", systemImage: "radio")
                    }
                    NavigationLink(value: SidebarItem.archiveNew) {
                        Label("Neu im Archiv", systemImage: "clock")
                    }
                    NavigationLink(value: SidebarItem.archive) {
                        Label("Archiv", systemImage: "archivebox")
                    }
                    #if os(iOS)
                    NavigationLink(value: SidebarItem.downloads) {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                    #endif

                    NavigationLink(value: SidebarItem.favoriteEpisodes) {
                        Label {
                            Text("Favoriten: Ausgaben")
                        } icon: {
                            Image(systemName: "heart.fill")
                        }
                    }
                    NavigationLink(value: SidebarItem.favoriteTracks) {
                        Label {
                            Text("Favoriten: Tracks")
                        } icon: {
                            Image(systemName: "heart.fill")
                        }
                    }

                    let favorites = apiClient.shows.filter { apiClient.isFavorite(show: $0) }
                    if !favorites.isEmpty {
                        Section(isExpanded: $isFavoritesExpanded) {
                            ForEach(favorites) { show in
                                NavigationLink(value: SidebarItem.show(show)) {
                                    Text(show.titel)
                                }
                            }
                        } header: {
                            Text("Favoriten")
                        }
                    }
                }
                .navigationTitle("BiteFM")
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 115, ideal: 165, max: 250)
            } detail: {
                Group {
                    switch selection {
                    case .archiveNew:
                        ArchiveNew()
                            .navigationTitle("Neu im Archiv")
                    case .archive:
                        ArchiveView()
                    #if os(iOS)
                    case .downloads:
                        DownloadsView()
                    #endif
                    case .favoriteEpisodes:
                        FavoriteEpisodesView()
                    case .favoriteTracks:
                        FavoriteTracksView()
                    case .show(let show):
                        BroadcastListView(show: show)
                            .id(show.id)
                    default:
                        LiveView()
                            .navigationTitle("Live")
                    }
                }
            }
        }
    }
}

/// iPhone (compact): hub for favorites instead of sidebar section.
///
/// Verwendet typisierte `NavigationLink(value:)`-Routen, damit der iPhone-Favoriten-Tab
/// seinen aktuellen Pfad serialisiert wiederherstellen kann.
private struct FavoritesHubView: View {
    @EnvironmentObject private var apiClient: APIClient

    var body: some View {
        List {
            Section {
                NavigationLink(value: AppRestorationState.DeepRoute.favoriteEpisodes) {
                    Label("Favoriten: Ausgaben", systemImage: "heart.text.square")
                }
                NavigationLink(value: AppRestorationState.DeepRoute.favoriteTracks) {
                    Label("Favoriten: Tracks", systemImage: "music.note")
                }
            }

            let favorites = apiClient.shows.filter { apiClient.isFavorite(show: $0) }
            if !favorites.isEmpty {
                Section("Favoriten-Sendungen") {
                    ForEach(favorites) { show in
                        NavigationLink(value: AppRestorationState.DeepRoute.show(slug: show.slug, title: show.titel, id: show.id)) {
                            Text(show.titel)
                        }
                    }
                }
            }
        }
        .navigationTitle("Favoriten")
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }
}

/// Mapper von `DeepRoute` auf konkrete Detail-Views — wird vom typisierten `NavigationStack`
/// im Favoriten-Tab über `navigationDestination(for:)` aufgerufen.
private struct FavoritesRouteDestination: View {
    @EnvironmentObject private var apiClient: APIClient
    let route: AppRestorationState.DeepRoute

    var body: some View {
        switch route {
        case .favoriteEpisodes:
            FavoriteEpisodesView()
        case .favoriteTracks:
            FavoriteTracksView()
        case .show(let slug, let title, let id):
            // Bevorzugt die zur Laufzeit verfügbare `Show`-Instanz; wenn die Sendung nicht mehr existiert,
            // bauen wir eine minimale Hülle, damit die Detailansicht nicht crasht.
            if let match = matchingShow(slug: slug, id: id) {
                BroadcastListView(show: match)
            } else {
                BroadcastListView(show: Show(id: id ?? -1, titel: title, untertitel: ""))
            }
        }
    }

    private func matchingShow(slug: String, id: Int?) -> Show? {
        if let id, let exact = apiClient.shows.first(where: { $0.id == id }) { return exact }
        return apiClient.shows.first(where: { $0.slug == slug })
    }
}

#Preview {
    ContentView()
        .environmentObject(APIClient.shared)
        .environmentObject(AudioPlayerManager.shared)
        .environmentObject(ActivePlaybackStore.shared)
        .environmentObject(PlaybackProgressStore.shared)
        #if os(iOS)
        .environmentObject(IOSDownloadManager.shared)
        #endif
}
