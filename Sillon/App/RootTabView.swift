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
    @Environment(\.playerController) private var playerController
    @State private var showPlayer = false

    var body: some View {
        TabView {
            Tab("Accueil", systemImage: "house.fill") {
                HomeView()
            }

            Tab("Bibliothèque", systemImage: "music.note.list") {
                LibraryRootView()
            }

            Tab("Favoris", systemImage: "heart.fill") {
                FavoritesView()
            }

            Tab("Réglages", systemImage: "gearshape.fill") {
                SettingsRootView()
            }
        }
        #if os(iOS)
        // Slot natif iOS 26 au-dessus de la barre d'onglets (façon Apple Music) : le mini-lecteur
        // n'empiète plus sur les onglets.
        .tabViewBottomAccessory {
            if playerController?.currentTrack != nil {
                NowPlayingBar { showPlayer = true }
            }
        }
        .fullScreenCover(isPresented: $showPlayer) { PlayerView() }
        #else
        .safeAreaInset(edge: .bottom) {
            if playerController?.currentTrack != nil {
                NowPlayingBar { showPlayer = true }
                    .padding(.vertical, Spacing.s)
                    .background(.thinMaterial)
            }
        }
        .sheet(isPresented: $showPlayer) { PlayerView().frame(minWidth: 360, minHeight: 600) }
        #endif
        #if DEBUG
        .task { await DebugBootstrap.runIfRequested(context: modelContext) }
        #endif
    }
}

#Preview("Vide (aucun serveur)") {
    RootTabView()
        .modelContainer(SillonSchema.makeContainer(inMemory: true))
}
