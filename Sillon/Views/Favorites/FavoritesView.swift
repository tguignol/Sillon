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

    var body: some View {
        NavigationStack {
            Group {
                if favoriteAlbums.isEmpty && favoriteTracks.isEmpty {
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
                if !favoriteTracks.isEmpty {
                    Button {
                        player?.play(queue: favoriteTracks.shuffled(), startAt: 0)
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

                if !favoriteAlbums.isEmpty {
                    sectionTitle("Albums")
                    LazyVGrid(columns: columns, spacing: Spacing.xl) {
                        ForEach(favoriteAlbums) { album in
                            NavigationLink(value: album) { AlbumCard(album: album) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.l)
                }

                if !favoriteTracks.isEmpty {
                    sectionTitle("Titres")
                    VStack(spacing: 0) {
                        ForEach(Array(favoriteTracks.enumerated()), id: \.element.id) { index, track in
                            TrackRowView(track: track, showsTrackNumber: false)
                                .padding(.horizontal, Spacing.l)
                                .padding(.vertical, Spacing.xs)
                                .contentShape(Rectangle())
                                .onTapGesture { player?.play(queue: favoriteTracks, startAt: index) }
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
