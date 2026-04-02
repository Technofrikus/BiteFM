import SwiftUI
#if os(iOS)
import UIKit
#endif

public struct ContentView: View {
    @EnvironmentObject private var apiClient: APIClient
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif

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
        #if os(iOS)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Defer the resume to the next run loop so scene activation can settle first.
                Task { @MainActor in
                    await Task.yield()
                    apiClient.resumeDeferredPollingIfConfigured()
                }
            case .background:
                apiClient.pauseDeferredPolling()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        #endif
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

    enum SidebarItem: Hashable {
        case live
        case archiveNew
        case archive
        case favoriteEpisodes
        case favoriteTracks
        case show(Show)
    }

    private enum MainTab: Hashable {
        case live
        case archiveNew
        case archive
        case favorites
    }

    @State private var selection: SidebarItem? = .live
    @State private var isFavoritesExpanded: Bool = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedTab: MainTab = .live
    @State private var logoutAlertPresented: Bool = false
    @State private var isNowPlayingExpanded: Bool = false

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
        VStack(spacing: 0) {
            if useCompactRoot {
                compactTabShell
            } else {
                splitShell
                PlayerBarView()
            }
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
    }

    /// Only mount the active tab to keep root-level subscribers lightweight on iPhone.
    #if os(iOS)
    @ViewBuilder
    private var compactTabShell: some View {
        if #available(iOS 26.1, *) {
            compactTabShellWithBottomAccessory
        } else {
            compactTabShellLegacyInset
        }
    }

    /// iOS 26.1+: System-Tab-Bottom-Accessory (`tabViewBottomAccessory(isEnabled:)`) + Tab-Leisten-Minimizer — erst ab 26.1 im SDK mit Deployment Target 17 aufrufbar.
    @available(iOS 26.1, *)
    private var compactTabShellWithBottomAccessory: some View {
        let miniActive = playerManager.currentItem != nil || playerManager.isLive
        return TabView(selection: $selectedTab) {
            Tab("Live", systemImage: "radio", value: MainTab.live) {
                NavigationStack {
                    Group {
                        if selectedTab == .live {
                            LiveView()
                        }
                    }
                    .navigationTitle("Live")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }

            Tab("Neu", systemImage: "clock", value: MainTab.archiveNew) {
                NavigationStack {
                    Group {
                        if selectedTab == .archiveNew {
                            ArchiveNew()
                        }
                    }
                    .navigationTitle("Neu im Archiv")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }

            Tab("Archiv", systemImage: "archivebox", value: MainTab.archive) {
                NavigationStack {
                    Group {
                        if selectedTab == .archive {
                            ArchiveView()
                        }
                    }
                }
            }

            Tab("Favoriten", systemImage: "heart.fill", value: MainTab.favorites) {
                NavigationStack {
                    Group {
                        if selectedTab == .favorites {
                            FavoritesHubView()
                        }
                    }
                    .navigationTitle("Favoriten")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .tabBarMinimizeBehavior(.automatic)
        .tabViewBottomAccessory(isEnabled: miniActive) {
            MiniPlayerBarView(onExpand: {
                isNowPlayingExpanded = true
            }, chrome: .tabAccessory)
            .environmentObject(playerManager)
        }
        .sheet(isPresented: $isNowPlayingExpanded) {
            ExpandedNowPlayingView()
                .environmentObject(apiClient)
                .environmentObject(playerManager)
                .presentationDragIndicator(.visible)
        }
    }

    /// iOS 17–26.0: `safeAreaInset` + klassische `tabItem`-Tabs (kein `tabViewBottomAccessory` im SDK bei älteren OS).
    private var compactTabShellLegacyInset: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                Group {
                    if selectedTab == .live {
                        LiveView()
                    }
                }
                .navigationTitle("Live")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Live", systemImage: "radio") }
            .tag(MainTab.live)

            NavigationStack {
                Group {
                    if selectedTab == .archiveNew {
                        ArchiveNew()
                    }
                }
                .navigationTitle("Neu im Archiv")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Neu", systemImage: "clock") }
            .tag(MainTab.archiveNew)

            NavigationStack {
                Group {
                    if selectedTab == .archive {
                        ArchiveView()
                    }
                }
            }
            .tabItem { Label("Archiv", systemImage: "archivebox") }
            .tag(MainTab.archive)

            NavigationStack {
                Group {
                    if selectedTab == .favorites {
                        FavoritesHubView()
                    }
                }
                .navigationTitle("Favoriten")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Favoriten", systemImage: "heart.fill") }
            .tag(MainTab.favorites)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if playerManager.currentItem != nil || playerManager.isLive {
                MiniPlayerBarView(onExpand: {
                    isNowPlayingExpanded = true
                }, chrome: .safeAreaInsetRow)
            }
        }
        .sheet(isPresented: $isNowPlayingExpanded) {
            ExpandedNowPlayingView()
                .environmentObject(apiClient)
                .environmentObject(playerManager)
                .presentationDragIndicator(.visible)
        }
    }
    #else
    private var compactTabShell: some View {
        EmptyView()
    }
    #endif

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

                    NavigationLink(value: SidebarItem.favoriteEpisodes) {
                        Label {
                            Text("Favoriten: Ausgaben")
                        } icon: {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.white)
                        }
                    }
                    NavigationLink(value: SidebarItem.favoriteTracks) {
                        Label {
                            Text("Favoriten: Tracks")
                        } icon: {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.white)
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
                .toolbar(removing: .sidebarToggle)
            } detail: {
                Group {
                    switch selection {
                    case .archiveNew:
                        ArchiveNew()
                            .navigationTitle("Neu im Archiv")
                    case .archive:
                        ArchiveView()
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
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    withAnimation {
                        columnVisibility = columnVisibility == .all ? .detailOnly : .all
                    }
                }) {
                    Label("Seitenleiste", systemImage: "sidebar.left")
                }
                .help("Seitenleiste ein-/ausblenden")
            }
        }
    }
}

/// iPhone (compact): hub for favorites instead of sidebar section.
private struct FavoritesHubView: View {
    @EnvironmentObject private var apiClient: APIClient

    var body: some View {
        List {
            Section {
                NavigationLink {
                    FavoriteEpisodesView()
                } label: {
                    Label("Favoriten: Ausgaben", systemImage: "heart.text.square")
                }
                NavigationLink {
                    FavoriteTracksView()
                } label: {
                    Label("Favoriten: Tracks", systemImage: "music.note")
                }
            }

            let favorites = apiClient.shows.filter { apiClient.isFavorite(show: $0) }
            if !favorites.isEmpty {
                Section("Favoriten-Sendungen") {
                    ForEach(favorites) { show in
                        NavigationLink {
                            BroadcastListView(show: show)
                        } label: {
                            Text(show.titel)
                        }
                    }
                }
            }
        }
        .navigationTitle("Favoriten")
    }
}

#Preview {
    ContentView()
        .environmentObject(APIClient.shared)
        .environmentObject(AudioPlayerManager.shared)
}
