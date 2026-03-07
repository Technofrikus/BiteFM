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
                        NavigationLink(value: "Archiv") {
                            Label("Neu im Archiv", systemImage: "clock")
                        }
                    }
                    .navigationTitle("ByteFM")
                    .listStyle(.sidebar)
                } detail: {
                    if selection == "Archiv" {
                        ArchiveView()
                            .navigationTitle("Neu im Archiv")
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
