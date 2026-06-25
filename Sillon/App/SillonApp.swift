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

    /// Apparence choisie par l'utilisateur (Réglages). Défaut : sombre (l'app est pensée sombre).
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.sombre.rawValue
    private var appearance: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .sombre }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.artworkLoader, artworkLoader)
                .environment(\.lyricsLoader, lyricsLoader)
                .environment(\.downloadManager, downloadManager)
                .environment(\.playerController, playerController)
                // Apparence pilotée par le réglage : `nil` (Système) suit l'appareil, sinon clair/sombre
                // imposé. La palette (Theme.swift) est adaptative, donc l'UI suit le schéma effectif.
                .preferredColorScheme(appearance.colorScheme)
                .task {
                    downloadManager.reconcileOnLaunch()
                    playerController.restoreLastSession()
                }
        }
        .modelContainer(modelContainer)
    }
}
