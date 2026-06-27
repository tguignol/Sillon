import SwiftUI
import SwiftData

struct ServerListView: View {
    // Ordonnés par priorité (sortOrder) : le 1er gagne en cas de doublon entre serveurs.
    @Query(sort: [SortDescriptor(\ServerAccount.sortOrder), SortDescriptor(\ServerAccount.createdAt)])
    private var servers: [ServerAccount]
    @Environment(\.modelContext) private var modelContext
    @AppStorage("mergeServerDuplicates") private var mergeDuplicates = true
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
                Section {
                    ForEach(servers) { server in
                        ServerRowView(
                            server: server,
                            syncState: viewModel.syncState(for: server.id),
                            onSyncTapped: { Task { await viewModel.synchronize(server, context: modelContext) } },
                            onSetActive: { isActive in
                                server.isActive = isActive
                                try? modelContext.save()
                            }
                        )
                    }
                    .onDelete { offsets in
                        let toDelete = offsets.map { servers[$0] }
                        for server in toDelete {
                            KeychainStore.deleteAll(for: server.id)
                            modelContext.delete(server)
                        }
                    }
                    .onMove { from, to in
                        var arr = servers
                        arr.move(fromOffsets: from, toOffset: to)
                        for (index, server) in arr.enumerated() { server.sortOrder = index }
                        try? modelContext.save()
                    }
                } footer: {
                    if servers.count > 1 {
                        Text("Le serveur du haut est prioritaire : sa copie est lue pour un album/titre présent sur plusieurs serveurs.")
                    }
                }

                if servers.count > 1 {
                    Section {
                        Toggle("Fusionner les doublons", isOn: $mergeDuplicates)
                            .tint(Palette.signalTeal)
                    } footer: {
                        Text("Affiche en un seul élément (badge « N sources ») un album ou un titre présent sur plusieurs serveurs.")
                    }
                }
            }
        }
        .navigationTitle(LanguageManager.string("Serveurs"))
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
        .task {
            // Initialise des priorités distinctes (par défaut : type — local>Jellyfin>Subsonic — puis
            // ancienneté) si elles ne le sont pas encore, pour un ordre stable et cohérent avec la dédup.
            guard !servers.isEmpty, Set(servers.map(\.sortOrder)).count != servers.count else { return }
            let ordered = servers.sorted {
                ($0.sortOrder, $0.type.dedupRank, $0.createdAt) < ($1.sortOrder, $1.type.dedupRank, $1.createdAt)
            }
            for (index, server) in ordered.enumerated() { server.sortOrder = index }
            try? modelContext.save()
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
