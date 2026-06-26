import SwiftUI
import SwiftData

/// Écran d'accueil — "votre disquaire personnel". Empilement de carrousels horizontaux : albums récents,
/// préférés, à redécouvrir, écoute en cours, pistes préférées, albums aléatoires, puis playlists. Les
/// sections vides sont masquées pour éviter un écran à trous. Les sélections aléatoires (« Redécouvrir »,
/// « Albums aléatoires ») sont figées par lancement (pas de re-mélange à chaque redessin).
struct HomeView: View {
    @Environment(\.playerController) private var player

    @Query(sort: \Album.dateAdded, order: .reverse) private var albumsByDate: [Album]
    @Query(filter: #Predicate<Album> { $0.isFavorite }, sort: \Album.favoriteDate, order: .reverse)
    private var favoriteAlbums: [Album]
    @Query(filter: #Predicate<Album> { $0.lastPlayedDate != nil }, sort: \Album.lastPlayedDate, order: .reverse)
    private var playedAlbums: [Album]
    @Query(filter: #Predicate<Track> { $0.isFavorite }, sort: \Track.favoriteDate, order: .reverse)
    private var favoriteTracks: [Track]
    @Query(sort: \Playlist.updatedAt, order: .reverse) private var playlists: [Playlist]

    /// Sélections aléatoires figées une fois la bibliothèque chargée (cf. `generateDiscoveryIfNeeded`).
    @State private var rediscoverAlbums: [Album] = []
    @State private var randomAlbums: [Album] = []

    private let albumCardSize: CGFloat = 160

    @AppStorage("mergeServerDuplicates") private var mergeDuplicates = true

    // Versions filtrées par serveurs actifs (les @Query agrègent tous les serveurs confondus).
    private var recentAlbums: [Album] { albumsByDate.onActiveServers() }
    private var activeFavoriteAlbums: [Album] { favoriteAlbums.onActiveServers() }
    private var activePlayedAlbums: [Album] { playedAlbums.onActiveServers() }
    private var activeFavoriteTracks: [Track] { favoriteTracks.onActiveServers() }

    /// Déduplique puis borne une liste d'albums pour un carrousel.
    private func entries(_ albums: [Album], limit: Int) -> [(album: Album, sourceCount: Int)] {
        Array(albums.dedupedAlbums(merge: mergeDuplicates).prefix(limit))
    }

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
        // Sélections figées filtrées au rendu : si un serveur est désactivé après leur génération,
        // ses albums disparaissent quand même de « Redécouvrir » / « Albums aléatoires ».
        // Représentants (déjà dédupliqués à la génération) → on les présente sans recomptage de sources.
        let rediscover = rediscoverAlbums.onActiveServers().map { (album: $0, sourceCount: 1) }
        let random = randomAlbums.onActiveServers().map { (album: $0, sourceCount: 1) }
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                albumCarousel("Albums récents", entries(recentAlbums, limit: 30))

                if !activeFavoriteAlbums.isEmpty {
                    albumCarousel("Albums préférés", entries(activeFavoriteAlbums, limit: 30))
                }

                if !rediscover.isEmpty {
                    albumCarousel("Redécouvrir des albums", rediscover)
                }

                if !activePlayedAlbums.isEmpty {
                    albumCarousel("Continuer l'écoute", entries(activePlayedAlbums, limit: 5))
                }

                if !activeFavoriteTracks.isEmpty {
                    let tracks = Array(activeFavoriteTracks.dedupedTracks(merge: mergeDuplicates).prefix(20))
                    HomeSection(title: "Pistes préférées") {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            Button {
                                player?.play(queue: tracks, startAt: index)
                            } label: {
                                TrackCard(track: track, size: 150)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !random.isEmpty {
                    albumCarousel("Albums aléatoires", random)
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
        .onAppear(perform: generateDiscoveryIfNeeded)
    }

    /// Carrousel d'albums standard (carte + navigation vers le détail).
    @ViewBuilder
    private func albumCarousel(_ title: String, _ entries: [(album: Album, sourceCount: Int)]) -> some View {
        HomeSection(title: title) {
            ForEach(entries, id: \.album.id) { entry in
                NavigationLink(value: entry.album) {
                    AlbumCard(album: entry.album, size: albumCardSize, sourceCount: entry.sourceCount)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Construit (une seule fois, une fois la bibliothèque chargée) les sélections « Redécouvrir » et
    /// « Albums aléatoires ». Figées pour la durée de vie de la vue → pas de re-mélange à chaque redessin
    /// (notamment quand `lastPlayedDate` change pendant la lecture) ; renouvelées au prochain lancement.
    private func generateDiscoveryIfNeeded() {
        guard randomAlbums.isEmpty, !recentAlbums.isEmpty else { return }
        // On tire parmi les représentants dédupliqués → pas de doublon entre serveurs dans les rangées.
        let deduped = recentAlbums.dedupedAlbums(merge: mergeDuplicates).map(\.album)
        randomAlbums = Array(deduped.shuffled().prefix(15))
        // « Redécouvrir » : priorité aux albums jamais lus (depuis l'ajout du champ) ; repli sur tout
        // le catalogue si trop peu d'albums jamais lus pour remplir la rangée.
        let neverPlayed = deduped.filter { $0.lastPlayedDate == nil }
        let pool = neverPlayed.count >= 15 ? neverPlayed : deduped
        rediscoverAlbums = Array(pool.shuffled().prefix(15))
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
