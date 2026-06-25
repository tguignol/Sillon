import SwiftUI
import SwiftData

struct ServerListView: View {
    @Query(sort: \ServerAccount.createdAt) private var servers: [ServerAccount]
    @Environment(\.modelContext) private var modelContext
    @State private var isPresentingAddServer = false
    @State private var viewModel = ServerListViewModel()

    var body: some View {
        List {
            if servers.isEmpty {
                ContentUnavailableView(
                    "Aucun serveur",
                    systemImage: "server.rack",
                    description: Text("Ajoutez un serveur Jellyfin, Navidrome/Subsonic ou un dossier local pour commencer.")
                )
            } else {
                ForEach(servers) { server in
                    ServerRowView(server: server, syncState: viewModel.syncState(for: server.id)) {
                        Task { await viewModel.synchronize(server, context: modelContext) }
                    }
                }
                .onDelete { offsets in
                    let toDelete = offsets.map { servers[$0] }
                    for server in toDelete {
                        KeychainStore.deleteAll(for: server.id)
                        modelContext.delete(server)
                    }
                }
            }
        }
        .navigationTitle("Serveurs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingAddServer = true
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingAddServer) {
            AddServerView()
        }
    }
}

#Preview("Sans serveur") {
    NavigationStack { ServerListView() }
        .modelContainer(SillonSchema.makeContainer(inMemory: true))
}

#Preview("Avec serveurs") {
    let container = SillonSchema.makeContainer(inMemory: true)
    container.mainContext.insert(ServerAccount(name: "Mon Jellyfin", type: .jellyfin, baseURLString: "https://exemple.local", username: "alex"))
    container.mainContext.insert(ServerAccount(name: "Navidrome maison", type: .subsonic, baseURLString: "https://exemple.local", username: "alex"))
    return NavigationStack { ServerListView() }
        .modelContainer(container)
}
