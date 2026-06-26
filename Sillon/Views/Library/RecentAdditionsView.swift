import SwiftUI
import SwiftData

/// Onglet « Ajout récent » de la bibliothèque : les albums triés par date d'ajout sur le serveur,
/// avec bascule entre plus récents d'abord (décroissant) et plus anciens d'abord (croissant).
struct RecentAdditionsView: View {
    @State private var ascending = false   // par défaut : plus récents d'abord

    var body: some View {
        VStack(spacing: 0) {
            Picker("Ordre", selection: $ascending) {
                Text("Plus récents").tag(false)
                Text("Plus anciens").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.s)

            RecentAlbumsGrid(ascending: ascending)
        }
    }
}

/// Grille des albums ordonnés par date d'ajout. Le `@Query` est reconstruit selon `ascending`
/// (le parent re-crée la vue au changement de l'ordre).
private struct RecentAlbumsGrid: View {
    @Query private var albums: [Album]
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Spacing.l)]

    init(ascending: Bool) {
        // Les albums sans date d'ajout (rare) tombent en fin de liste grâce au tri secondaire par titre.
        _albums = Query(sort: [
            SortDescriptor(\Album.dateAdded, order: ascending ? .forward : .reverse),
            SortDescriptor(\Album.title)
        ])
    }

    @AppStorage("mergeServerDuplicates") private var mergeDuplicates = true
    private var visibleAlbums: [(album: Album, sourceCount: Int)] {
        albums.onActiveServers().dedupedAlbums(merge: mergeDuplicates)
    }

    var body: some View {
        if visibleAlbums.isEmpty {
            LibraryEmptyState(title: "Aucun album", systemImage: "clock")
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.xl) {
                    ForEach(visibleAlbums, id: \.album.id) { entry in
                        NavigationLink { AlbumDetailView(album: entry.album) } label: {
                            AlbumCard(album: entry.album, sourceCount: entry.sourceCount)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.l)
            }
        }
    }
}
