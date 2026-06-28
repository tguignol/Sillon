import SwiftUI
import SwiftData

/// Racine de l'onglet Bibliothèque : un sélecteur segmenté bascule entre Artistes, Albums, Titres
/// et Playlists. Les quatre sous-vues partagent la même `NavigationStack` (les `navigationDestination`
/// y sont résolus), ce qui garde une pile de navigation cohérente quand on passe d'une section à l'autre.
struct LibraryRootView: View {
    enum Section: String, CaseIterable, Identifiable {
        // Ordre d'affichage du sélecteur (suit la déclaration via CaseIterable).
        case ajoutRecent = "Récents"
        case artistes = "Artistes"
        case albums = "Albums"
        case titres = "Titres"
        case playlists = "Playlists"
        var id: String { rawValue }
    }

    @State private var section: Section = .albums
    @State private var searchText = ""
    @State private var albumSort: AlbumSortOrder = .titre
    @State private var sortDescending = false   // bascule A→Z / Z→A (façon Android)

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    SearchResultsView(query: searchText)
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
            .navigationTitle(LanguageManager.string("Bibliothèque"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: "Artistes, albums, titres")
            .toolbar {
                if !isSearching {
                    if section == .albums {
                        ToolbarItem(placement: .primaryAction) { sortMenu }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink { BrowseRootView() } label: {
                            Image(systemName: "rectangle.3.group")
                        }
                    }
                }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Trier les albums", selection: $albumSort) {
                ForEach(AlbumSortOrder.allCases) { order in
                    Label(order.label, systemImage: order.systemImage).tag(order)
                }
            }
            Divider()
            // Sens du tri (A→Z / Z→A), façon Android.
            Picker("Sens", selection: $sortDescending) {
                Label("A → Z", systemImage: "arrow.down").tag(false)
                Label("Z → A", systemImage: "arrow.up").tag(true)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .artistes: ArtistsListView()
        case .albums: AlbumsGridView(sort: albumSort, descending: sortDescending)
        case .titres: TracksListView()
        case .playlists: PlaylistsListView()
        case .ajoutRecent: RecentAdditionsView()
        }
    }
}

/// État vide partagé par les sections de bibliothèque quand aucune donnée n'a encore été synchronisée.
struct LibraryEmptyState: View {
    var title: LocalizedStringKey = "Bibliothèque vide"
    var message: LocalizedStringKey = "Ajoutez un serveur dans Réglages, puis lancez une synchronisation pour voir votre musique ici."
    var systemImage: String = "music.note.list"

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Vide") {
    LibraryRootView()
        .modelContainer(SillonSchema.makeContainer(inMemory: true))
}

#Preview("Avec données") {
    let container = SillonSchema.makeContainer(inMemory: true)
    PreviewData.populate(container.mainContext)
    return LibraryRootView()
        .modelContainer(container)
}
