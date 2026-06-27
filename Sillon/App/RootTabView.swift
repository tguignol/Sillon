import SwiftUI
import SwiftData

/// Squelette de navigation : Accueil, Bibliothèque, Favoris, Réglages, plus un mini-lecteur ancré
/// au-dessus de la barre d'onglets dès qu'un morceau est en cours.
///
/// Note multiplateforme : `TabView` fonctionne nativement sur iOS et macOS. Sur macOS/iPadOS,
/// une navigation par `NavigationSplitView` (sidebar façon Apple Music) sera évaluée plus tard —
/// décision différée, la `TabView` reste cohérente entre plateformes pour l'instant.
struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.playerController) private var playerController
    @Query private var servers: [ServerAccount]
    #if os(iOS)
    @State private var showPlayer = false
    #endif

    private var hasNowPlaying: Bool { playerController?.currentTrack != nil }

    var body: some View {
        Group {
            #if os(iOS)
            // iOS/iPadOS : navigation par onglets, lecteur en plein écran.
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

                // Recherche globale (toute la bibliothèque, tous serveurs actifs) — intercalée avant Réglages.
                Tab("Recherche", systemImage: "magnifyingglass") {
                    SearchView()
                }

                Tab("Réglages", systemImage: "gearshape.fill") {
                    SettingsRootView()
                }
            }
            .modifier(NowPlayingAccessory(show: hasNowPlaying) { showPlayer = true })
            .fullScreenCover(isPresented: $showPlayer) { PlayerView() }
            #else
            // macOS : barre latérale + lecteur en deux colonnes dans la zone de détail.
            MacSidebarRootView()
            #endif
        }
        // Les pastilles de source n'ont de sens qu'avec ≥2 serveurs ACTIFS : si un seul est activé,
        // tout provient de la même source — pastilles masquées (et déduplication des titres
        // court-circuitée, cf. TracksListView/BrowseViews qui gardent `&& hasMultipleServers`).
        .environment(\.hasMultipleServers, servers.filter(\.isActive).count > 1)
        #if DEBUG
        .task { await DebugBootstrap.runIfRequested(context: modelContext) }
        #endif
    }
}

#if os(iOS)
/// Ancre le mini-lecteur uniquement quand un morceau est en cours — évite la capsule vide quand
/// rien ne joue. iOS 26 : slot natif `tabViewBottomAccessory` au-dessus de la barre d'onglets.
/// (Sur macOS, c'est `MacSidebarRootView` qui ancre son propre mini-lecteur.)
private struct NowPlayingAccessory: ViewModifier {
    let show: Bool
    let onTap: () -> Void

    func body(content: Content) -> some View {
        if show {
            content.tabViewBottomAccessory { NowPlayingBar(onTap: onTap) }
        } else {
            content
        }
    }
}
#endif

#Preview("Vide (aucun serveur)") {
    RootTabView()
        .modelContainer(SillonSchema.makeContainer(inMemory: true))
}
