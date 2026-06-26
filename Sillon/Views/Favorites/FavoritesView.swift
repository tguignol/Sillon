import SwiftUI
import SwiftData

/// Onglet Favoris : deux sections séparées par un sélecteur segmenté — « Albums » (grille) et
/// « Titres » (liste + « Mixer les favoris »), pour ne pas mélanger les deux. Le cœur se bascule
/// partout ailleurs (détails, lecteur, menus contextuels).
struct FavoritesView: View {
    enum Section: String, CaseIterable, Identifiable {
        case albums = "Albums"
        case titres = "Titres"
        var id: String { rawValue }
    }

    @Query(filter: #Predicate<Album> { $0.isFavorite }, sort: \Album.favoriteDate, order: .reverse)
    private var favoriteAlbums: [Album]
    @Query(filter: #Predicate<Track> { $0.isFavorite }, sort: \Track.favoriteDate, order: .reverse)
    private var favoriteTracks: [Track]

    @Environment(\.playerController) private var player
    @Environment(\.modelContext) private var context

    @State private var section: Section = .albums

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
                    VStack(spacing: 0) {
                        Picker("Section", selection: $section) {
                            ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(Spacing.l)

                        Divider()

                        content
                    }
                }
            }
            .navigationTitle("Favoris")
            .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
        }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .albums: albumsContent
        case .titres: tracksContent
        }
    }

    // MARK: - Albums

    @ViewBuilder private var albumsContent: some View {
        if visibleAlbums.isEmpty {
            emptyTab("Aucun album favori", message: "Touchez le cœur sur un album pour le retrouver ici.")
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.xl) {
                    ForEach(visibleAlbums, id: \.album.id) { entry in
                        NavigationLink(value: entry.album) {
                            AlbumCard(album: entry.album, sourceCount: entry.sourceCount)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.l)
            }
        }
    }

    // MARK: - Titres

    @ViewBuilder private var tracksContent: some View {
        if visibleTracks.isEmpty {
            emptyTab("Aucun titre favori", message: "Touchez le cœur sur un titre pour le retrouver ici.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    HStack {
                        Spacer()
                        Button {
                            player?.play(queue: visibleTracks.shuffled(), startAt: 0)
                        } label: {
                            Label("Mixer les favoris", systemImage: "shuffle")
                                .font(.headline)
                                .padding(.vertical, Spacing.xs)
                                .padding(.horizontal, Spacing.m)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.accentCuivre)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.l)

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
                .padding(.vertical, Spacing.l)
            }
        }
    }

    private func emptyTab(_ title: String, message: String) -> some View {
        ContentUnavailableView(title, systemImage: "heart", description: Text(message))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    let container = SillonSchema.makeContainer(inMemory: true)
    PreviewData.populate(container.mainContext)
    return FavoritesView()
        .modelContainer(container)
}
