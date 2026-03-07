import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var apiClient: APIClient
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
                        VStack(spacing: 10) {
                            Text("Live")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text("Live-Stream ist in dieser Version noch nicht aktiv.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                PlayerBarView()
            }
        } else {
            LoginView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(APIClient.shared)
        .environmentObject(AudioPlayerManager.shared)
}
