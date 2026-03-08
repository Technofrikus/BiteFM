import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @State private var selection: String? = "Live"

    var body: some View {
        if apiClient.isLoggedIn {
            VStack(spacing: 0) {
                NavigationSplitView {
                    List(selection: $selection) {
                        NavigationLink(value: "Live") {
                            Label("Live", systemImage: "radio")
                        }
                        NavigationLink(value: "ArchivNeu") {
                            Label("Neu im Archiv", systemImage: "clock")
                        }
                        NavigationLink(value: "Archiv") {
                            Label("Archiv", systemImage: "archivebox")
                        }
                    }
                    .navigationTitle("ByteFM")
                    .listStyle(.sidebar)
                } detail: {
                    if selection == "ArchivNeu" {
                        ArchiveNew()
                            .navigationTitle("Neu im Archiv")
                    } else if selection == "Archiv" {
                        ArchiveView()
                            .navigationTitle("Archiv")
                    } else {
                        LiveView()
                            .navigationTitle("Live")
                    }
                }

                PlayerBarView()
            }
        } else {
            LoginView()
                .task {
                    await apiClient.autoLogin()
                }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(APIClient.shared)
        .environmentObject(AudioPlayerManager.shared)
}
