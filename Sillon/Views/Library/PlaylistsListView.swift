import SwiftUI
import SwiftData

/// Liste des playlists locales : création, suppression, navigation vers le détail (réordonnancement).
struct PlaylistsListView: View {
    @Query(sort: \Playlist.updatedAt, order: .reverse) private var playlists: [Playlist]
    @Environment(\.modelContext) private var context
    @State private var showCreate = false
    @State private var newName = ""

    var body: some View {
        Group {
            if playlists.isEmpty {
                ContentUnavailableView(
                    "Aucune playlist",
                    systemImage: "music.note.list",
                    description: Text("Créez une playlist avec le bouton +, ou ajoutez des titres depuis la bibliothèque (appui long sur un titre).")
                )
            } else {
                List {
                    ForEach(playlists) { playlist in
                        NavigationLink(value: playlist) { row(playlist) }
                    }
                    .onDelete { offsets in
                        for index in offsets where playlists.indices.contains(index) {
                            PlaylistActions.delete(playlists[index], context: context)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { newName = ""; showCreate = true } label: {
                    Label("Nouvelle playlist", systemImage: "plus")
                }
            }
        }
        .alert("Nouvelle playlist", isPresented: $showCreate) {
            TextField("Nom", text: $newName)
            Button("Créer") { PlaylistActions.create(name: newName, context: context) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Donnez un nom à votre playlist.")
        }
    }

    private func row(_ playlist: Playlist) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "music.note.list")
                .foregroundStyle(Palette.accentCuivre)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name).font(.headline)
                Text("\(playlist.items.count) titre\(playlist.items.count > 1 ? "s" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack { PlaylistsListView() }
        .modelContainer(SillonSchema.makeContainer(inMemory: true))
}
