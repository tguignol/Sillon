#if os(macOS)
import SwiftUI

/// Racine macOS dédiée : navigation par **barre latérale** (façon Apple Music / Finder) au lieu des
/// onglets, et **lecteur en deux colonnes** affiché en grand dans la zone de détail (la fenêtre Mac
/// est large → `PlayerView` y bascule automatiquement sur sa disposition paysage).
///
/// iOS/iPadOS gardent la `TabView` plein écran (cf. `RootTabView`) : seules la navigation et la
/// présentation du lecteur diffèrent — toutes les vues de contenu (grilles, listes, cartes) sont
/// réutilisées telles quelles.
struct MacSidebarRootView: View {
    @Environment(\.playerController) private var player
    @State private var selection: MacSection? = .accueil
    /// Quand vrai, la zone de détail montre le lecteur plein format à la place de la section courante.
    @State private var showPlayer = false

    private var hasNowPlaying: Bool { player?.currentTrack != nil }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(MacSection.allCases) { section in
                    Label(section.label, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 172, ideal: 196, max: 240)
        } detail: {
            Group {
                if showPlayer, hasNowPlaying {
                    // Lecteur en ligne (pas une feuille) : la barre latérale reste visible à côté.
                    PlayerView(onClose: { showPlayer = false })
                } else {
                    section(selection ?? .accueil)
                        // Mini-lecteur ancré en bas de la zone de détail dès qu'un morceau est en cours ;
                        // tapé, il déploie le lecteur plein format. `safeAreaInset` décale le contenu au-dessus.
                        .safeAreaInset(edge: .bottom) {
                            if hasNowPlaying {
                                NowPlayingBar(onTap: { showPlayer = true })
                                    .padding(.vertical, Spacing.s)
                                    .padding(.horizontal, Spacing.m)
                                    .background(.thinMaterial)
                            }
                        }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showPlayer)
        }
        // Choisir une section dans la barre latérale referme le lecteur et montre cette section.
        .onChange(of: selection) { _, _ in showPlayer = false }
    }

    @ViewBuilder
    private func section(_ s: MacSection) -> some View {
        switch s {
        case .accueil: HomeView()
        case .bibliotheque: LibraryRootView()
        case .favoris: FavoritesView()
        case .recherche: SearchView()
        case .reglages: SettingsRootView()
        }
    }
}

/// Entrées de la barre latérale macOS — mêmes destinations que les onglets iOS.
enum MacSection: String, CaseIterable, Identifiable {
    case accueil, bibliotheque, favoris, recherche, reglages

    var id: String { rawValue }

    var label: String {
        switch self {
        case .accueil: LanguageManager.string("Accueil")
        case .bibliotheque: LanguageManager.string("Bibliothèque")
        case .favoris: LanguageManager.string("Favoris")
        case .recherche: LanguageManager.string("Recherche")
        case .reglages: LanguageManager.string("Réglages")
        }
    }

    var systemImage: String {
        switch self {
        case .accueil: "house.fill"
        case .bibliotheque: "music.note.list"
        case .favoris: "heart.fill"
        case .recherche: "magnifyingglass"
        case .reglages: "gearshape.fill"
        }
    }
}
#endif
