import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Racine de navigation, adaptée à la plateforme et au format :
/// - **iPhone** (et **iPad en portrait**) : onglets en bas + lecteur en plein écran.
/// - **iPad en paysage** et **macOS** : barre latérale (`SidebarRootView`, façon Apple Music) +
///   lecteur en deux colonnes dans la zone de détail.
/// Toutes les vues de contenu sont communes ; seules la navigation et la présentation du lecteur diffèrent.
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
            if UIDevice.current.userInterfaceIdiom == .pad {
                // iPad : barre latérale en PAYSAGE (comme macOS), onglets en portrait.
                GeometryReader { geo in
                    if geo.size.width > geo.size.height {
                        SidebarRootView()
                    } else {
                        tabRoot
                    }
                }
            } else {
                tabRoot   // iPhone : toujours des onglets
            }
            #else
            SidebarRootView()   // macOS : toujours la barre latérale
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

    #if os(iOS)
    /// Navigation par onglets + lecteur en plein écran (iPhone, et iPad en portrait).
    private var tabRoot: some View {
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
    }
    #endif
}

#if os(iOS)
/// Ancre le mini-lecteur uniquement quand un morceau est en cours — évite la capsule vide quand
/// rien ne joue. iOS 26 : slot natif `tabViewBottomAccessory` au-dessus de la barre d'onglets.
/// (En mode barre latérale, c'est `SidebarRootView` qui ancre son propre mini-lecteur.)
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
