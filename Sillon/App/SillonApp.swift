import SwiftUI
import SwiftData

@main
struct SillonApp: App {
    let modelContainer: ModelContainer

    #if os(iOS)
    @UIApplicationDelegateAdaptor(SillonAppDelegate.self) private var appDelegate
    #endif

    init() {
        let container = SillonSchema.makeContainer()
        modelContainer = container
        let downloads = DownloadManager(container: container)
        _downloadManager = State(initialValue: downloads)
        _playerController = State(initialValue: PlayerController(container: container, downloadManager: downloads))
    }

    /// Loader de pochettes partagé par toute l'app (cache des providers authentifiés + des URLs résolues).
    @State private var artworkLoader = ArtworkLoader()

    /// Loader de paroles partagé (récupération à la demande, lecture seule, cache par morceau).
    @State private var lyricsLoader = LyricsLoader()

    /// Gestionnaire de téléchargements partagé (session URLSession de fond).
    @State private var downloadManager: DownloadManager

    /// Contrôleur de lecture audio partagé (moteur AVAudioEngine + EQ).
    @State private var playerController: PlayerController

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.artworkLoader, artworkLoader)
                .environment(\.lyricsLoader, lyricsLoader)
                .environment(\.downloadManager, downloadManager)
                .environment(\.playerController, playerController)
                // Le système de design est sombre par nature (cf. Docs/DESIGN_SYSTEM.md : fond noir,
                // texte ivoire, accents cuivre/teal). On impose donc l'apparence sombre de l'app
                // (uniquement l'app — pas le réglage clair/sombre du système).
                .preferredColorScheme(.dark)
                .task {
                    downloadManager.reconcileOnLaunch()
                    playerController.restoreLastSession()
                }
        }
        .modelContainer(modelContainer)
    }
}
