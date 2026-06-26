import SwiftUI
import SwiftData

/// Point d'entrée « Parcourir » : navigation par genre ou par décennie.
struct BrowseRootView: View {
    var body: some View {
        List {
            NavigationLink { GenresListView() } label: {
                Label("Par genre", systemImage: "guitars")
            }
            NavigationLink { DecadesListView() } label: {
                Label("Par décennie", systemImage: "calendar")
            }
        }
        .navigationTitle("Parcourir")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Genres

/// Liste des genres présents dans la bibliothèque. On ne charge que la colonne `genre` (partiel) pour
/// éviter de matérialiser tous les morceaux, puis on déduplique en mémoire.
struct GenresListView: View {
    @Environment(\.modelContext) private var context
    @State private var genres: [String] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if genres.isEmpty && loaded {
                ContentUnavailableView("Aucun genre", systemImage: "guitars",
                                       description: Text("Les genres apparaîtront après une synchronisation."))
            } else {
                List(genres, id: \.self) { genre in
                    NavigationLink {
                        GenreTracksView(genre: genre)
                    } label: {
                        Label(genre, systemImage: "guitars")
                    }
                }
            }
        }
        .navigationTitle("Genres")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            // On lit la relation `server` pour filtrer les serveurs actifs → pas de propertiesToFetch.
            let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.genre != nil })
            let tracks = ((try? context.fetch(descriptor)) ?? []).onActiveServers()
            genres = Set(tracks.compactMap { g in
                let v = g.genre?.trimmingCharacters(in: .whitespaces)
                return (v?.isEmpty == false) ? v : nil
            }).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            loaded = true
        }
    }
}

/// Morceaux d'un genre donné, jouables comme une file.
struct GenreTracksView: View {
    let genre: String
    @Environment(\.playerController) private var player
    @Environment(\.modelContext) private var context
    @Query private var tracks: [Track]

    init(genre: String) {
        self.genre = genre
        _tracks = Query(filter: #Predicate { $0.genre == genre }, sort: [SortDescriptor(\.title)])
    }

    private var visibleTracks: [Track] { tracks.onActiveServers() }

    var body: some View {
        List {
            ForEach(Array(visibleTracks.enumerated()), id: \.element.id) { index, track in
                TrackRowView(track: track)
                    .contentShape(Rectangle())
                    .onTapGesture { player?.play(queue: visibleTracks, startAt: index) }
                    .trackContextMenu(track: track, context: context)
            }
        }
        .listStyle(.plain)
        .navigationTitle(genre)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !visibleTracks.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        player?.play(queue: visibleTracks.shuffled(), startAt: 0)
                    } label: { Label("Mélanger", systemImage: "shuffle") }
                }
            }
        }
    }
}

// MARK: - Décennies

/// Liste des décennies présentes (déduites de `Album.year`, déjà stocké → pas de migration).
struct DecadesListView: View {
    @Query(sort: [SortDescriptor(\Album.year, order: .reverse)]) private var albums: [Album]

    private var decades: [Int] {
        Set(albums.onActiveServers().compactMap { $0.year.flatMap { $0 > 0 ? ($0 / 10) * 10 : nil } }).sorted(by: >)
    }

    var body: some View {
        Group {
            if decades.isEmpty {
                ContentUnavailableView("Aucune année", systemImage: "calendar")
            } else {
                List(decades, id: \.self) { decade in
                    NavigationLink {
                        DecadeAlbumsView(decade: decade)
                    } label: {
                        // String(decade) évite le séparateur de milliers ajouté par le format locale.
                        Label("\(String(decade))s", systemImage: "calendar")
                    }
                }
            }
        }
        .navigationTitle("Décennies")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Albums d'une décennie donnée.
struct DecadeAlbumsView: View {
    let decade: Int
    @Query private var albums: [Album]
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Spacing.l)]

    init(decade: Int) {
        self.decade = decade
        let lo = decade, hi = decade + 9
        _albums = Query(filter: #Predicate { ($0.year ?? 0) >= lo && ($0.year ?? 0) <= hi },
                        sort: [SortDescriptor(\.year), SortDescriptor(\.title)])
    }

    private var visibleAlbums: [Album] { albums.onActiveServers() }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Spacing.xl) {
                ForEach(visibleAlbums) { album in
                    NavigationLink { AlbumDetailView(album: album) } label: { AlbumCard(album: album) }
                        .buttonStyle(.plain)
                }
            }
            .padding(Spacing.l)
        }
        .navigationTitle("\(String(decade))s")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
