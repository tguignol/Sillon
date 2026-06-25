import SwiftUI
import SwiftData

/// Écran d'accueil — "votre disquaire personnel". Sections horizontales défilantes : « Ajouts récents »
/// (30 derniers albums ajoutés au serveur, par date) et « Albums préférés » (albums favoris) en grand
/// format, puis « Playlists » en format réduit. Les sections vides sont masquées pour éviter un écran à trous.
struct HomeView: View {
    @Query(sort: \Album.dateAdded, order: .reverse) private var recentAlbums: [Album]
    @Query(filter: #Predicate<Album> { $0.isFavorite }, sort: \Album.favoriteDate, order: .reverse)
    private var favoriteAlbums: [Album]
    @Query(sort: \Playlist.updatedAt, order: .reverse) private var playlists: [Playlist]

    var body: some View {
        NavigationStack {
            Group {
                if recentAlbums.isEmpty {
                    LibraryEmptyState(
                        title: "Votre disquaire est vide",
                        message: "Ajoutez un serveur dans Réglages, puis lancez une synchronisation pour retrouver votre musique ici.",
                        systemImage: "opticaldisc"
                    )
                } else {
                    content
                }
            }
            .navigationTitle("Accueil")
            .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
            .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                HomeSection(title: "Ajouts récents") {
                    ForEach(Array(recentAlbums.prefix(30))) { album in
                        NavigationLink(value: album) {
                            AlbumCard(album: album, size: 180)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !favoriteAlbums.isEmpty {
                    HomeSection(title: "Albums préférés") {
                        ForEach(Array(favoriteAlbums.prefix(30))) { album in
                            NavigationLink(value: album) {
                                AlbumCard(album: album, size: 180)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !playlists.isEmpty {
                    HomeSection(title: "Playlists") {
                        ForEach(playlists.prefix(12)) { playlist in
                            NavigationLink(value: playlist) {
                                PlaylistChip(playlist: playlist)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.vertical, Spacing.l)
        }
    }
}

/// Bandeau titre + rangée horizontale défilante. Le contenu fixe sa propre taille de carte,
/// ce qui permet les formats inégaux entre sections.
private struct HomeSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(title)
                .font(Typo.displaySmall)
                .foregroundStyle(Palette.texteIvoire)
                .padding(.horizontal, Spacing.l)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Spacing.l) {
                    content
                }
                .padding(.horizontal, Spacing.l)
            }
        }
    }
}

private struct PlaylistChip: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            RoundedRectangle(cornerRadius: Spacing.cardCorner, style: .continuous)
                .fill(Palette.surfaceElevee)
                .frame(width: 130, height: 130)
                .overlay(
                    Image(systemName: "music.note.list")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Palette.accentCuivre)
                )
            Text(playlist.name)
                .font(.subheadline)
                .foregroundStyle(Palette.texteIvoire)
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)
        }
    }
}

#Preview("Avec données") {
    let container = SillonSchema.makeContainer(inMemory: true)
    PreviewData.populate(container.mainContext)
    return HomeView()
        .modelContainer(container)
}

#Preview("Vide") {
    HomeView()
        .modelContainer(SillonSchema.makeContainer(inMemory: true))
}
