import SwiftUI
import SwiftData

/// Onglet **Recherche** dédié : une barre de recherche toujours présente dont la requête porte sur
/// TOUTE la bibliothèque (tous les serveurs actifs confondus, via `SearchResultsView`). La recherche
/// est donc globale quel que soit l'endroit d'où on l'ouvre — c'est le point d'entrée plein écran,
/// en plus de la barre `.searchable` de la Bibliothèque.
struct SearchView: View {
    @State private var query = ""

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    SearchResultsView(query: query)
                } else {
                    ContentUnavailableView(
                        "Rechercher",
                        systemImage: "magnifyingglass",
                        description: Text("Artistes, albums et titres dans toute votre bibliothèque, tous serveurs confondus.")
                    )
                }
            }
            .navigationTitle("Recherche")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $query, prompt: "Artistes, albums, titres")
        }
    }
}

#Preview {
    let container = SillonSchema.makeContainer(inMemory: true)
    PreviewData.populate(container.mainContext)
    return SearchView()
        .modelContainer(container)
}
