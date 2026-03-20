import SwiftUI

struct ContentView: View {
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
    
    @State private var selection: SidebarItem? = .live
    @State private var isFavoritesExpanded: Bool = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if apiClient.isLoggedIn {
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
                    
                    PlayerBarView()
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
            } else {
                LoginView()
                    .task {
                        await apiClient.autoLogin()
                    }
            }
        }
        .alert("Abmelden?", isPresented: $apiClient.showLogoutConfirmation) {
            Button("Abbrechen", role: .cancel) { }
            Button("Abmelden", role: .destructive) {
                apiClient.logout()
            }
        } message: {
            Text("Wenn Sie sich abmelden, werden alle Daten (gespeicherte Sendungen 'Neu im Archiv') gelöscht. Diese sind nicht wiederherzustellen.")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(APIClient.shared)
        .environmentObject(AudioPlayerManager.shared)
}
