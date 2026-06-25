import SwiftUI
import SwiftData

/// Liste des playlists locales à l'app, les plus récemment modifiées en tête.
///
/// Périmètre Phase 1 : les playlists sont créées/gérées côté app (modèle `Playlist`, UUID local) ;
/// les playlists *distantes* ne sont pas importées par la synchro (cf. Docs/DECISIONS.md #14).
/// La création/édition (CRUD + réordonnancement) arrive au commit "Favoris + Playlists".
struct PlaylistsListView: View {
    @Query(sort: \Playlist.updatedAt, order: .reverse) private var playlists: [Playlist]

    var body: some View {
        if playlists.isEmpty {
            LibraryEmptyState(
                title: "Aucune playlist",
                message: "La création de playlists arrivera dans une prochaine étape.",
                systemImage: "music.note.list"
            )
        } else {
            List(playlists) { playlist in
                HStack(spacing: Spacing.m) {
                    Image(systemName: "music.note.list")
                        .foregroundStyle(Palette.accentCuivre)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playlist.name)
                            .font(.headline)
                        Text("\(playlist.items.count) titre\(playlist.items.count > 1 ? "s" : "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

#Preview {
    NavigationStack { PlaylistsListView() }
        .modelContainer(SillonSchema.makeContainer(inMemory: true))
}
