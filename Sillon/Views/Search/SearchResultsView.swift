import SwiftUI
import SwiftData

/// Résultats de recherche locale unifiée (artistes / albums / titres) sur la bibliothèque déjà
/// synchronisée — instantané et hors connexion. Recherche insensible à la casse et aux accents
/// (`localizedStandardContains`), bornée par type pour rester fluide même sur de grosses bibliothèques.
struct SearchResultsView: View {
    let query: String

    @Environment(\.modelContext) private var context
    @Environment(\.playerController) private var player

    @State private var artists: [Artist] = []
    @State private var albums: [Album] = []
    @State private var tracks: [Track] = []

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
        .task(id: query) { runSearch() }
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

        var artistDesc = FetchDescriptor<Artist>(
            predicate: #Predicate { $0.name.localizedStandardContains(q) },
            sortBy: [SortDescriptor(\.sortName)])
        artistDesc.fetchLimit = 20
        artists = (try? context.fetch(artistDesc)) ?? []

        var albumDesc = FetchDescriptor<Album>(
            predicate: #Predicate { $0.title.localizedStandardContains(q) },
            sortBy: [SortDescriptor(\.title)])
        albumDesc.fetchLimit = 20
        albums = (try? context.fetch(albumDesc)) ?? []

        var trackDesc = FetchDescriptor<Track>(
            predicate: #Predicate { $0.title.localizedStandardContains(q) },
            sortBy: [SortDescriptor(\.title)])
        trackDesc.fetchLimit = 50
        tracks = (try? context.fetch(trackDesc)) ?? []
    }
}
