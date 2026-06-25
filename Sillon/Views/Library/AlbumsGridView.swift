import SwiftUI
import SwiftData

/// Grille des albums, triés par titre. Mène au détail d'album (liste des morceaux).
struct AlbumsGridView: View {
    @Query(sort: \Album.title) private var albums: [Album]

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Spacing.l)]

    var body: some View {
        Group {
            if albums.isEmpty {
                LibraryEmptyState(title: "Aucun album", systemImage: "square.stack")
            } else {
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
            }
        }
        .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
    }
}

/// Détail d'un album : en-tête (pochette + métadonnées) puis liste ordonnée des morceaux.
struct AlbumDetailView: View {
    let album: Album

    private var orderedTracks: [Track] {
        album.tracks.sorted {
            ($0.discNumber ?? 1, $0.trackNumber ?? 0, $0.title)
                < ($1.discNumber ?? 1, $1.trackNumber ?? 0, $1.title)
        }
    }

    var body: some View {
        List {
            Section {
                header
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, Spacing.s)
            }
            Section {
                ForEach(orderedTracks) { track in
                    TrackRowView(track: track, showsTrackNumber: true)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(album.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.l) {
            CoverArtView(path: album.coverArtRemotePath, server: album.server, seed: album.title)
                .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(album.title)
                    .font(Typo.displaySmall)
                    .foregroundStyle(Palette.texteIvoire)
                if let artist = album.artistNameSnapshot ?? album.artist?.name {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(metadataLine)
                    .font(Typo.technique)
                    .foregroundStyle(Palette.signalTeal)
                    .padding(.top, Spacing.xs)
            }
            Spacer(minLength: 0)
        }
    }

    private var metadataLine: String {
        var parts: [String] = []
        if let year = album.year { parts.append(String(year)) }
        let count = album.tracks.count
        parts.append("\(count) titre\(count > 1 ? "s" : "")")
        let total = album.tracks.reduce(0) { $0 + $1.durationSeconds }
        if total > 0 { parts.append(total.asTrackDuration) }
        return parts.joined(separator: " · ")
    }
}

#Preview("Grille") {
    let container = SillonSchema.makeContainer(inMemory: true)
    PreviewData.populate(container.mainContext)
    return NavigationStack { AlbumsGridView() }
        .modelContainer(container)
}
