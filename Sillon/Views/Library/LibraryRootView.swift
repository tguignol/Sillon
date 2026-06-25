import SwiftUI
import SwiftData

/// Racine de l'onglet Bibliothèque : un sélecteur segmenté bascule entre Artistes, Albums, Titres
/// et Playlists. Les quatre sous-vues partagent la même `NavigationStack` (les `navigationDestination`
/// y sont résolus), ce qui garde une pile de navigation cohérente quand on passe d'une section à l'autre.
struct LibraryRootView: View {
    enum Section: String, CaseIterable, Identifiable {
        case artistes = "Artistes"
        case albums = "Albums"
        case titres = "Titres"
        case playlists = "Playlists"
        var id: String { rawValue }
    }

    @State private var section: Section = .albums

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(Spacing.l)

                Divider()

                content
            }
            .navigationTitle("Bibliothèque")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .artistes: ArtistsListView()
        case .albums: AlbumsGridView()
        case .titres: TracksListView()
        case .playlists: PlaylistsListView()
        }
    }
}

/// État vide partagé par les sections de bibliothèque quand aucune donnée n'a encore été synchronisée.
struct LibraryEmptyState: View {
    var title: String = "Bibliothèque vide"
    var message: String = "Ajoutez un serveur dans Réglages, puis lancez une synchronisation pour voir votre musique ici."
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
