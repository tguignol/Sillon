import SwiftUI
import SwiftData

/// Squelette de navigation. Accueil et Bibliothèque sont désormais réels (commit "Synchronisation +
/// Bibliothèque") ; Favoris reste un placeholder jusqu'au commit "Favoris + Playlists". L'onglet
/// Réglages héberge la gestion des serveurs (commit "Gestion des serveurs + providers réseau").
///
/// Note multiplateforme : `TabView` fonctionne nativement sur iOS et macOS. Sur macOS/iPadOS,
/// une navigation par `NavigationSplitView` (sidebar façon Apple Music) sera évaluée plus tard —
/// décision différée, la `TabView` reste cohérente entre plateformes pour l'instant.
struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            Tab("Accueil", systemImage: "house.fill") {
                HomeView()
            }

            Tab("Bibliothèque", systemImage: "music.note.list") {
                LibraryRootView()
            }

            Tab("Favoris", systemImage: "heart.fill") {
                PlaceholderScreen(title: "Favoris", systemImage: "heart.fill")
            }

            Tab("Réglages", systemImage: "gearshape.fill") {
                SettingsRootView()
            }
        }
        #if DEBUG
        .task { await DebugBootstrap.runIfRequested(context: modelContext) }
        #endif
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
