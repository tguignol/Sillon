import SwiftUI
import SwiftData

/// Liste des artistes, triés par nom de tri (`sortName`). Chaque ligne mène au détail de l'artiste.
struct ArtistsListView: View {
    @Query(sort: \Artist.sortName) private var artists: [Artist]

    private var visibleArtists: [Artist] { artists.onActiveServers() }

    var body: some View {
        Group {
            if visibleArtists.isEmpty {
                LibraryEmptyState(title: "Aucun artiste", systemImage: "music.mic")
            } else {
                List(visibleArtists) { artist in
                    NavigationLink(value: artist) {
                        ArtistRow(artist: artist)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationDestination(for: Artist.self) { ArtistDetailView(artist: $0) }
    }
}

private struct ArtistRow: View {
    let artist: Artist

    var body: some View {
        HStack(spacing: Spacing.m) {
            CoverArtView(
                path: artist.coverArtRemotePath,
                server: artist.server,
                seed: artist.name,
                symbol: "music.mic"
            )
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(artist.albums.count) album\(artist.albums.count > 1 ? "s" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if artist.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.accentCuivre)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Détail d'un artiste : ses albums en grille.
struct ArtistDetailView: View {
    let artist: Artist
    @Environment(\.modelContext) private var context

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Spacing.l)]

    private var albums: [Album] {
        artist.albums.onActiveServers().sorted { ($0.year ?? 0, $0.title) < ($1.year ?? 0, $1.title) }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Spacing.xl) {
                ForEach(albums) { album in
                    NavigationLink(value: album) {
                        AlbumCard(album: album)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.l)
        }
        .navigationTitle(artist.name)
        .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                FavoriteButton(isFavorite: artist.isFavorite, prominent: true) {
                    Favorites.toggle(artist, context: context)
                }
            }
        }
    }
}

#Preview {
    let container = SillonSchema.makeContainer(inMemory: true)
    PreviewData.populate(container.mainContext)
    return NavigationStack { ArtistsListView() }
        .modelContainer(container)
}
