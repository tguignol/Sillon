import SwiftUI
import SwiftData

/// Onglet Favoris : albums et titres mis en favori, plus « Mixer les favoris » (lecture aléatoire de
/// tous les titres favoris). Le cœur se bascule partout ailleurs (détails, lecteur, menus contextuels).
struct FavoritesView: View {
    @Query(filter: #Predicate<Album> { $0.isFavorite }, sort: \Album.favoriteDate, order: .reverse)
    private var favoriteAlbums: [Album]
    @Query(filter: #Predicate<Track> { $0.isFavorite }, sort: \Track.favoriteDate, order: .reverse)
    private var favoriteTracks: [Track]

    @Environment(\.playerController) private var player
    @Environment(\.modelContext) private var context

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Spacing.l)]

    @AppStorage("mergeServerDuplicates") private var mergeDuplicates = true
    private var visibleAlbums: [(album: Album, sourceCount: Int)] {
        favoriteAlbums.onActiveServers().dedupedAlbums(merge: mergeDuplicates)
    }
    private var visibleTracks: [Track] {
        favoriteTracks.onActiveServers().dedupedTracks(merge: mergeDuplicates)
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleAlbums.isEmpty && visibleTracks.isEmpty {
                    ContentUnavailableView(
                        "Aucun favori",
                        systemImage: "heart",
                        description: Text("Touchez le cœur sur un artiste, un album ou un titre pour le retrouver ici.")
                    )
                } else {
                    content
                }
            }
            .navigationTitle("Favoris")
            .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if !visibleTracks.isEmpty {
                    Button {
                        player?.play(queue: visibleTracks.shuffled(), startAt: 0)
                    } label: {
                        Label("Mixer les favoris", systemImage: "shuffle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.m)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accentCuivre)
                    .padding(.horizontal, Spacing.l)
                }

                if !visibleAlbums.isEmpty {
                    sectionTitle("Albums")
                    LazyVGrid(columns: columns, spacing: Spacing.xl) {
                        ForEach(visibleAlbums, id: \.album.id) { entry in
                            NavigationLink(value: entry.album) {
                                AlbumCard(album: entry.album, sourceCount: entry.sourceCount)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.l)
                }

                if !visibleTracks.isEmpty {
                    sectionTitle("Titres")
                    VStack(spacing: 0) {
                        ForEach(Array(visibleTracks.enumerated()), id: \.element.id) { index, track in
                            TrackRowView(track: track, showsTrackNumber: false, showsArtwork: true)
                                .padding(.horizontal, Spacing.l)
                                .padding(.vertical, Spacing.xs)
                                .contentShape(Rectangle())
                                .onTapGesture { player?.play(queue: visibleTracks, startAt: index) }
                                .trackContextMenu(track: track, context: context)
                        }
                    }
                }
            }
            .padding(.vertical, Spacing.l)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(Typo.displaySmall)
            .foregroundStyle(Palette.texteIvoire)
            .padding(.horizontal, Spacing.l)
    }
}

#Preview {
    let container = SillonSchema.makeContainer(inMemory: true)
    PreviewData.populate(container.mainContext)
    return FavoritesView()
        .modelContainer(container)
}
