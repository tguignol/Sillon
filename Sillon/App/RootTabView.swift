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
    @State private var showPlayer = false

    private var hasNowPlaying: Bool { playerController?.currentTrack != nil }

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
        // Les pastilles de source n'apparaissent qu'avec ≥2 serveurs configurés (sinon redondantes).
        .environment(\.hasMultipleServers, servers.count > 1)
        .modifier(NowPlayingAccessory(show: hasNowPlaying) { showPlayer = true })
        #if os(iOS)
        .fullScreenCover(isPresented: $showPlayer) { PlayerView() }
        #else
        .sheet(isPresented: $showPlayer) { PlayerView().frame(minWidth: 360, minHeight: 600) }
        #endif
        #if DEBUG
        .task { await DebugBootstrap.runIfRequested(context: modelContext) }
        #endif
    }
}

/// Ancre le mini-lecteur uniquement quand un morceau est en cours — évite la capsule vide quand
/// rien ne joue. iOS 26 : slot natif `tabViewBottomAccessory` ; macOS : `safeAreaInset`.
private struct NowPlayingAccessory: ViewModifier {
    let show: Bool
    let onTap: () -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        if show {
            content.tabViewBottomAccessory { NowPlayingBar(onTap: onTap) }
        } else {
            content
        }
        #else
        content.safeAreaInset(edge: .bottom) {
            if show {
                NowPlayingBar(onTap: onTap)
                    .padding(.vertical, Spacing.s)
                    .background(.thinMaterial)
            }
        }
        #endif
    }
}

#Preview("Vide (aucun serveur)") {
    RootTabView()
        .modelContainer(SillonSchema.makeContainer(inMemory: true))
}
