import SwiftUI
import SwiftData

/// Squelette de navigation. Accueil/Bibliothèque/Favoris restent des placeholders à ce stade
/// (commits "Synchronisation + Bibliothèque" et "Favoris + Playlists") ; l'onglet Réglages héberge
/// déjà la gestion des serveurs (commit "Gestion des serveurs + providers réseau").
///
/// Note multiplateforme : `TabView` fonctionne nativement sur iOS et macOS. Sur macOS/iPadOS,
/// une navigation par `NavigationSplitView` (sidebar façon Apple Music) sera évaluée à l'étape
/// "Bibliothèque" — décision différée car elle dépend des vraies données à afficher.
struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Accueil", systemImage: "house.fill") {
                PlaceholderScreen(title: "Accueil", systemImage: "house.fill")
            }

            Tab("Bibliothèque", systemImage: "music.note.list") {
                PlaceholderScreen(title: "Bibliothèque", systemImage: "music.note.list")
            }

            Tab("Favoris", systemImage: "heart.fill") {
                PlaceholderScreen(title: "Favoris", systemImage: "heart.fill")
            }

            Tab("Réglages", systemImage: "gearshape.fill") {
                SettingsRootView()
            }
        }
    }
}

private struct PlaceholderScreen: View {
    let title: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text("Cet écran sera construit dans une prochaine étape.")
            )
            .navigationTitle(title)
        }
    }
}

#Preview("Vide (aucun serveur)") {
    RootTabView()
        .modelContainer(SillonSchema.makeContainer(inMemory: true))
}
