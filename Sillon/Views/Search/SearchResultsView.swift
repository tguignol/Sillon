import SwiftUI
import SwiftData

/// Résultats de recherche locale unifiée (artistes / albums / titres) sur la bibliothèque déjà
/// synchronisée — instantané et hors connexion. Recherche insensible à la casse et aux accents
/// (`localizedStandardContains`), bornée par type pour rester fluide même sur de grosses bibliothèques.
struct SearchResultsView: View {
    let query: String

    @Environment(\.modelContext) private var context
    @Environment(\.playerController) private var player
    // @Query se réévalue à chaque save du contexte (y compris un toggle isActive) → permet de relancer
    // la recherche quand l'ensemble des serveurs actifs change.
    @Query private var servers: [ServerAccount]
    @AppStorage("mergeServerDuplicates") private var mergeDuplicates = true

    @State private var artists: [Artist] = []
    @State private var albums: [Album] = []
    @State private var tracks: [Track] = []

    /// Signature stable de l'ensemble des serveurs actifs, injectée dans l'id du `.task`.
    private var activeSignature: String {
        servers.filter(\.isActive).map { $0.id.uuidString }.sorted().joined(separator: ",")
    }

    var body: some View {
        Group {
            if artists.isEmpty && albums.isEmpty && tracks.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List {
                    if !artists.isEmpty {
                        Section("Artistes") {
                            ForEach(artists) { artist in
                                NavigationLink(value: artist) { artistRow(artist) }
                            }
                        }
                    }
                    if !albums.isEmpty {
                        Section("Albums") {
                            ForEach(albums) { album in
                                NavigationLink(value: album) { albumRow(album) }
                            }
                        }
                    }
                    if !tracks.isEmpty {
                        Section("Titres") {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                TrackRowView(track: track, showsTrackNumber: false)
                                    .contentShape(Rectangle())
                                    .onTapGesture { player?.play(queue: tracks, startAt: index) }
                                    .trackContextMenu(track: track, context: context)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationDestination(for: Artist.self) { ArtistDetailView(artist: $0) }
        .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
        .task(id: "\(query)|\(activeSignature)|\(mergeDuplicates)") { runSearch() }
    }

    private func artistRow(_ artist: Artist) -> some View {
        HStack(spacing: Spacing.m) {
            CoverArtView(path: artist.coverArtRemotePath, server: artist.server, seed: artist.name, symbol: "music.mic")
                .frame(width: 40, height: 40)
            Text(artist.name).font(.headline).lineLimit(1)
        }
    }

    private func albumRow(_ album: Album) -> some View {
        HStack(spacing: Spacing.m) {
            CoverArtView(path: album.coverArtRemotePath, server: album.server, seed: album.title)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title).font(.headline).lineLimit(1)
                if let artist = album.artistNameSnapshot ?? album.artist?.name {
                    Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 1 else { artists = []; albums = []; tracks = []; return }

        // On élargit la limite de fetch (× nb de serveurs actifs) puis on filtre par serveurs actifs et
        // on déduplique, pour qu'un serveur désactivé ou des doublons miroir ne réduisent pas les résultats.
        let factor = max(1, servers.filter(\.isActive).count)

        var artistDesc = FetchDescriptor<Artist>(
            predicate: #Predicate { $0.name.localizedStandardContains(q) },
            sortBy: [SortDescriptor(\.sortName)])
        artistDesc.fetchLimit = 20 * factor
        artists = Array(((try? context.fetch(artistDesc)) ?? [])
            .onActiveServers().dedupedArtists(merge: mergeDuplicates).prefix(20))

        var albumDesc = FetchDescriptor<Album>(
            predicate: #Predicate { $0.title.localizedStandardContains(q) },
            sortBy: [SortDescriptor(\.title)])
        albumDesc.fetchLimit = 20 * factor
        albums = Array(((try? context.fetch(albumDesc)) ?? [])
            .onActiveServers().dedupedAlbums(merge: mergeDuplicates).map(\.album).prefix(20))

        var trackDesc = FetchDescriptor<Track>(
            predicate: #Predicate { $0.title.localizedStandardContains(q) },
            sortBy: [SortDescriptor(\.title)])
        trackDesc.fetchLimit = 50 * factor
        tracks = Array(((try? context.fetch(trackDesc)) ?? [])
            .onActiveServers().dedupedTracks(merge: mergeDuplicates).prefix(50))
    }
}
