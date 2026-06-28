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
    @Query(filter: #Predicate<Album> { $0.playCount > 0 }, sort: \Album.playCount, order: .reverse)
    private var mostPlayedAlbums: [Album]
    @Query(filter: #Predicate<Track> { $0.playCount > 0 }, sort: \Track.playCount, order: .reverse)
    private var mostPlayedTracks: [Track]
    @Query(sort: \Playlist.updatedAt, order: .reverse) private var playlists: [Playlist]

    /// Sélections aléatoires figées une fois la bibliothèque chargée (cf. `generateDiscoveryIfNeeded`).
    @State private var rediscoverAlbums: [Album] = []
    @State private var randomAlbums: [Album] = []
    /// Incrémenté à chaque re-mélange manuel (« Redécouvrir » ou « Aléatoires ») — déclenche le retour haptique.
    @State private var shuffleToken = 0

    private let albumCardSize: CGFloat = 160

    @AppStorage("mergeServerDuplicates") private var mergeDuplicates = true

    // Versions filtrées par serveurs actifs (les @Query agrègent tous les serveurs confondus).
    private var recentAlbums: [Album] { albumsByDate.onActiveServers() }
    private var activeFavoriteAlbums: [Album] { favoriteAlbums.onActiveServers() }
    private var activePlayedAlbums: [Album] { playedAlbums.onActiveServers() }
    private var activeFavoriteTracks: [Track] { favoriteTracks.onActiveServers() }
    private var activeMostPlayedAlbums: [Album] { mostPlayedAlbums.onActiveServers() }
    private var activeMostPlayedTracks: [Track] { mostPlayedTracks.onActiveServers() }

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
            .navigationTitle(LanguageManager.string("Accueil"))
            // Toute la navigation de l'Accueil est value-based : les destinations sont déclarées UNE
            // seule fois ici, à la racine, et desservent aussi bien les carrousels que les vues
            // poussées par les accès rapides (qui s'appuient dessus via `providesNavigationDestination:
            // false`). Mélanger des `NavigationLink` à destination directe casserait cette résolution.
            .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
            .navigationDestination(for: Artist.self) { ArtistDetailView(artist: $0, providesNavigationDestination: false) }
            .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
            .navigationDestination(for: HomeSeeAllView.Kind.self) { HomeSeeAllView(kind: $0) }
            .navigationDestination(for: QuickDestination.self) { destination in
                switch destination {
                case .albums:
                    AlbumsGridView(providesNavigationDestination: false)
                        .navigationTitle(LanguageManager.string("Albums"))
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                case .artistes:
                    ArtistsListView(providesNavigationDestination: false)
                        .navigationTitle(LanguageManager.string("Artistes"))
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                }
            }
        }
    }

    /// Cibles des accès rapides en haut de l'Accueil (poussées sur la même pile, en value-based).
    private enum QuickDestination: Hashable {
        case albums, artistes
    }

    private var content: some View {
        // Sélections figées filtrées au rendu : si un serveur est désactivé après leur génération,
        // ses albums disparaissent quand même de « Redécouvrir » / « Albums aléatoires ».
        // Représentants (déjà dédupliqués à la génération) → on les présente sans recomptage de sources.
        let rediscover = rediscoverAlbums.onActiveServers().map { (album: $0, sourceCount: 1) }
        let random = randomAlbums.onActiveServers().map { (album: $0, sourceCount: 1) }
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                quickActions

                // Ordre aligné sur l'Accueil Android.
                albumCarousel("Albums récents", entries(recentAlbums, limit: 30), seeAll: .recents)

                if !activeMostPlayedTracks.isEmpty {
                    let tracks = Array(activeMostPlayedTracks.dedupedTracks(merge: mergeDuplicates).prefix(20))
                    HomeSection(title: "Titres les plus écoutés", seeAll: .mostPlayedTracks) {
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

                if !activePlayedAlbums.isEmpty {
                    albumCarousel("Albums écoutés récemment", entries(activePlayedAlbums, limit: 30), seeAll: .playedAlbums)
                }

                if !activeMostPlayedAlbums.isEmpty {
                    albumCarousel("Les plus écoutés", entries(activeMostPlayedAlbums, limit: 30), seeAll: .mostPlayedAlbums)
                }

                if !activeFavoriteTracks.isEmpty {
                    let tracks = Array(activeFavoriteTracks.dedupedTracks(merge: mergeDuplicates).prefix(20))
                    HomeSection(title: "Pistes préférées", seeAll: .favoriteTracks) {
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

                if !activeFavoriteAlbums.isEmpty {
                    albumCarousel("Albums préférés", entries(activeFavoriteAlbums, limit: 30), seeAll: .favoriteAlbums)
                }

                if !random.isEmpty {
                    // Overscroll à l'un des bords → nouveau tirage.
                    albumCarousel("Albums aléatoires", random, onEdgeOverscroll: regenerateRandom)
                }

                if !rediscover.isEmpty {
                    // Tirer le carrousel au-delà de l'un de ses bords re-mélange la sélection (comme au démarrage).
                    albumCarousel("Redécouvrir des albums", rediscover, onEdgeOverscroll: regenerateRediscover)
                }

                // (iOS-only) Playlists, en fin de liste.
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
        // Petit retour haptique à chaque re-mélange de « Redécouvrir » (no-op sur macOS).
        .sensoryFeedback(.impact(weight: .light), trigger: shuffleToken)
    }

    /// Accès rapides en haut de l'Accueil : Albums, Artistes, Mixer les favoris.
    /// (La Recherche a son propre onglet dédié dans la barre du bas — toujours globale.)
    private var quickActions: some View {
        HStack(spacing: Spacing.m) {
            NavigationLink(value: QuickDestination.albums) {
                QuickAction(title: "Albums", systemImage: "square.stack.fill")
            }

            NavigationLink(value: QuickDestination.artistes) {
                QuickAction(title: "Artistes", systemImage: "music.mic")
            }

            Button {
                let tracks = activeFavoriteTracks.dedupedTracks(merge: mergeDuplicates)
                guard !tracks.isEmpty else { return }
                player?.play(queue: tracks.shuffled(), startAt: 0)
            } label: {
                QuickAction(title: "Mixer les favoris", systemImage: "shuffle")
            }
            .disabled(activeFavoriteTracks.isEmpty)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.l)
    }

    /// Carrousel d'albums standard (carte + navigation vers le détail). `onEdgeOverscroll`, s'il est
    /// fourni, est appelé quand on tire la rangée au-delà de l'un de ses bords (cf. « Redécouvrir »).
    @ViewBuilder
    private func albumCarousel(_ title: LocalizedStringKey,
                               _ entries: [(album: Album, sourceCount: Int)],
                               seeAll: HomeSeeAllView.Kind? = nil,
                               onEdgeOverscroll: (() -> Void)? = nil) -> some View {
        HomeSection(title: title, seeAll: seeAll, onEdgeOverscroll: onEdgeOverscroll) {
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

    /// Re-tire une sélection aléatoire pour « Redécouvrir » (même logique que la génération initiale,
    /// sans le garde-fou). Déclenché par un overscroll à l'un des bords du carrousel (gauche ou droite).
    private func regenerateRediscover() {
        guard !recentAlbums.isEmpty else { return }
        let deduped = recentAlbums.dedupedAlbums(merge: mergeDuplicates).map(\.album)
        let neverPlayed = deduped.filter { $0.lastPlayedDate == nil }
        let pool = neverPlayed.count >= 15 ? neverPlayed : deduped
        withAnimation(.easeInOut(duration: 0.3)) {
            rediscoverAlbums = Array(pool.shuffled().prefix(15))
        }
        shuffleToken += 1
    }

    /// Re-tire la sélection « Albums aléatoires » (tirage uniforme dans tout le catalogue dédupliqué).
    /// Déclenché par un overscroll à l'un des bords du carrousel (gauche ou droite).
    private func regenerateRandom() {
        guard !recentAlbums.isEmpty else { return }
        let deduped = recentAlbums.dedupedAlbums(merge: mergeDuplicates).map(\.album)
        withAnimation(.easeInOut(duration: 0.3)) {
            randomAlbums = Array(deduped.shuffled().prefix(15))
        }
        shuffleToken += 1
    }
}

/// Bandeau titre + rangée horizontale défilante. Le contenu fixe sa propre taille de carte,
/// ce qui permet les formats inégaux entre sections.
///
/// `onEdgeOverscroll` (optionnel) est appelé quand l'utilisateur tire la rangée au-delà de l'un de ses
/// bords (gauche OU droite) — geste « pull-to-refresh » horizontal. Armé/désarmé par seuil pour ne se
/// déclencher qu'une fois par geste, et seulement attaché si l'action est fournie (zéro surcoût
/// d'observation du défilement pour les autres carrousels).
private struct HomeSection<Content: View>: View {
    let title: LocalizedStringKey
    /// Destination « voir tout » (chevron à droite du titre) ; nil ⇒ pas de chevron.
    var seeAll: HomeSeeAllView.Kind? = nil
    var onEdgeOverscroll: (() -> Void)? = nil
    @ViewBuilder let content: Content

    /// Réarmé quand on revient près du bord ; évite de re-déclencher en continu tant qu'on tire.
    @State private var overscrollArmed = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Text(title)
                    .font(Typo.displaySmall)
                    .foregroundStyle(Palette.texteIvoire)
                Spacer()
                if let seeAll {
                    NavigationLink(value: seeAll) {
                        Image(systemName: "chevron.right")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.l)

            row
        }
    }

    @ViewBuilder private var row: some View {
        let scroll = ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Spacing.l) {
                content
            }
            .padding(.horizontal, Spacing.l)
        }

        if let onEdgeOverscroll {
            scroll.onScrollGeometryChange(for: CGFloat.self) { geo in
                // Distance tirée AU-DELÀ d'un bord, gauche OU droite (> 0 en overscroll ; ≤ 0 sinon).
                let leading = -geo.contentOffset.x
                let trailing = geo.contentOffset.x - max(0, geo.contentSize.width - geo.containerSize.width)
                return max(leading, trailing)
            } action: { _, overscroll in
                if overscroll > 70, overscrollArmed {
                    overscrollArmed = false
                    onEdgeOverscroll()
                } else if overscroll < 20 {
                    overscrollArmed = true
                }
            }
        } else {
            scroll
        }
    }
}

/// Carte d'accès rapide (icône + libellé) affichée en haut de l'Accueil.
private struct QuickAction: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Palette.signalTeal)
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Palette.texteIvoire)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(Palette.surfaceElevee, in: RoundedRectangle(cornerRadius: Spacing.cardCorner, style: .continuous))
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
