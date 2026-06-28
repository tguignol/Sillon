import SwiftUI

/// Racine à **barre latérale** (façon Apple Music / Finder) : navigation `NavigationSplitView` +
/// lecteur en deux colonnes affiché dans la zone de détail. Utilisée sur **macOS** (toujours) et sur
/// **iPad en paysage** ; iPhone et iPad en portrait gardent la `TabView` plein écran (cf. `RootTabView`).
///
/// La barre latérale offre nativement un bouton de repli (masquage complet) — identique à Apple Music.
/// Toutes les vues de contenu (grilles, listes, cartes) sont réutilisées telles quelles.
struct SidebarRootView: View {
    @Environment(\.playerController) private var player
    @State private var selection: SidebarSection? = .accueil
    /// Quand vrai, la zone de détail montre le lecteur plein format à la place de la section courante.
    @State private var showPlayer = false

    private var hasNowPlaying: Bool { player?.currentTrack != nil }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarSection.allCases) { section in
                    Label(section.label, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 172, ideal: 196, max: 240)
        } detail: {
            detailArea
                .animation(.easeInOut(duration: 0.2), value: showPlayer)
        }
        // Mini-lecteur ancré au bas de TOUTE la fenêtre (au niveau du split, pas de la section) →
        // TOUJOURS visible : accueil, bibliothèque ET détail d'album (façon Android, comme en portrait).
        .safeAreaInset(edge: .bottom) {
            if hasNowPlaying && !showPlayer {
                NowPlayingBar(onTap: { showPlayer = true })
                    .padding(.vertical, Spacing.s)
                    .padding(.horizontal, Spacing.m)
                    .background(.thinMaterial)
            }
        }
        #if os(iOS)
        // iPad : lecteur plein écran présenté en MODAL (`fullScreenCover`), exactement comme en portrait
        // (cf. RootTabView). Indispensable : une simple surimpression ZStack empêchait les UI système
        // (ex. téléchargement du modèle de langue pour la TRADUCTION des paroles) de s'afficher → la
        // traduction ne marchait pas en paysage. Le modal glisse depuis le bas (même rendu).
        .fullScreenCover(isPresented: $showPlayer) {
            if hasNowPlaying { PlayerView() }
        }
        #endif
        // Choisir une section dans la barre latérale referme le lecteur et montre cette section.
        .onChange(of: selection) { _, _ in showPlayer = false }
    }

    /// Zone de détail. macOS : le lecteur s'affiche EN LIGNE (barre latérale visible, façon Apple Music).
    /// iOS (iPad) : toujours la section ; le lecteur plein format est en surimpression (cf. ZStack).
    @ViewBuilder private var detailArea: some View {
        #if os(macOS)
        if showPlayer, hasNowPlaying {
            PlayerView(onClose: { showPlayer = false })
        } else {
            section(selection ?? .accueil)
        }
        #else
        section(selection ?? .accueil)
        #endif
    }

    @ViewBuilder
    private func section(_ s: SidebarSection) -> some View {
        switch s {
        case .accueil: HomeView()
        case .bibliotheque: LibraryRootView()
        case .favoris: FavoritesView()
        case .recherche: SearchView()
        case .reglages: SettingsRootView()
        }
    }
}

/// Entrées de la barre latérale — mêmes destinations que les onglets iPhone.
enum SidebarSection: String, CaseIterable, Identifiable {
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
