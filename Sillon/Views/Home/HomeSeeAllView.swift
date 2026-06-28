import SwiftUI
import SwiftData

/// Vue « voir tout » d'une section d'accueil : grille d'albums ou liste de titres, listant TOUT le
/// contenu de la section (au-delà du carrousel). Réutilise `AlbumCard` / `TrackCard` et la même
/// déduplication + filtrage par serveurs actifs que l'accueil.
struct HomeSeeAllView: View {
    enum Kind: Hashable {
        case recents, mostPlayedTracks, mostPlayedAlbums, favoriteAlbums, favoriteTracks, playedAlbums

        var title: String {
            switch self {
            case .recents: return "Albums récents"
            case .mostPlayedTracks: return "Titres les plus écoutés"
            case .mostPlayedAlbums: return "Les plus écoutés"
            case .favoriteAlbums: return "Albums préférés"
            case .favoriteTracks: return "Pistes préférées"
            case .playedAlbums: return "Continuer l'écoute"
            }
        }
        var isTracks: Bool { self == .mostPlayedTracks || self == .favoriteTracks }
    }

    let kind: Kind
    @Environment(\.playerController) private var player
    @AppStorage("mergeServerDuplicates") private var mergeDuplicates = true
    @Query private var albums: [Album]
    @Query private var tracks: [Track]

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Spacing.l)]

    init(kind: Kind) {
        self.kind = kind
        switch kind {
        case .recents:
            _albums = Query(sort: \Album.dateAdded, order: .reverse)
            _tracks = Query(filter: #Predicate<Track> { _ in false }, sort: \Track.title)
        case .mostPlayedAlbums:
            _albums = Query(filter: #Predicate<Album> { $0.playCount > 0 }, sort: \Album.playCount, order: .reverse)
            _tracks = Query(filter: #Predicate<Track> { _ in false }, sort: \Track.title)
        case .favoriteAlbums:
            _albums = Query(filter: #Predicate<Album> { $0.isFavorite }, sort: \Album.favoriteDate, order: .reverse)
            _tracks = Query(filter: #Predicate<Track> { _ in false }, sort: \Track.title)
        case .playedAlbums:
            _albums = Query(filter: #Predicate<Album> { $0.lastPlayedDate != nil }, sort: \Album.lastPlayedDate, order: .reverse)
            _tracks = Query(filter: #Predicate<Track> { _ in false }, sort: \Track.title)
        case .mostPlayedTracks:
            _tracks = Query(filter: #Predicate<Track> { $0.playCount > 0 }, sort: \Track.playCount, order: .reverse)
            _albums = Query(filter: #Predicate<Album> { _ in false }, sort: \Album.title)
        case .favoriteTracks:
            _tracks = Query(filter: #Predicate<Track> { $0.isFavorite }, sort: \Track.favoriteDate, order: .reverse)
            _albums = Query(filter: #Predicate<Album> { _ in false }, sort: \Album.title)
        }
    }

    private var albumEntries: [(album: Album, sourceCount: Int)] {
        albums.onActiveServers().dedupedAlbums(merge: mergeDuplicates)
    }
    private var trackList: [Track] {
        tracks.onActiveServers().dedupedTracks(merge: mergeDuplicates)
    }

    var body: some View {
        ScrollView {
            if kind.isTracks {
                let list = trackList
                LazyVGrid(columns: columns, spacing: Spacing.xl) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, track in
                        Button {
                            player?.play(queue: list, startAt: index)
                        } label: {
                            TrackCard(track: track)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.l)
            } else {
                LazyVGrid(columns: columns, spacing: Spacing.xl) {
                    ForEach(albumEntries, id: \.album.id) { entry in
                        NavigationLink(value: entry.album) {
                            AlbumCard(album: entry.album, sourceCount: entry.sourceCount)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.l)
            }
        }
        .background(Palette.fondNoir)
        .navigationTitle(LanguageManager.string(kind.title))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
