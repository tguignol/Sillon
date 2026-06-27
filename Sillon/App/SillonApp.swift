import SwiftUI
import SwiftData

@main
struct SillonApp: App {
    let modelContainer: ModelContainer

    #if os(iOS)
    @UIApplicationDelegateAdaptor(SillonAppDelegate.self) private var appDelegate
    #elseif os(macOS)
    // Fermer la dernière fenêtre quitte l'app (pas de lecture qui continue en arrière-plan).
    @NSApplicationDelegateAdaptor(SillonMacAppDelegate.self) private var macAppDelegate
    #endif

    init() {
        // Redirige Bundle.main vers la langue choisie (avant tout affichage de texte).
        LanguageManager.bootstrap()
        let container = SillonSchema.makeContainer()
        modelContainer = container
        let downloads = DownloadManager(container: container)
        _downloadManager = State(initialValue: downloads)
        _playerController = State(initialValue: PlayerController(container: container, downloadManager: downloads))
    }

    /// Langue d'interface choisie (Réglages ▸ Langue). `system` = langue de l'appareil.
    @AppStorage(LanguageManager.storageKey) private var languageRaw = AppLanguage.system.rawValue
    private var appLanguage: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .system }

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
                // Langue de l'app : `locale` pour les formats, `.id` pour forcer la reconstruction
                // complète (et donc la re-traduction de tous les textes) au changement de langue.
                .environment(\.locale, appLanguage.localeCode.map(Locale.init(identifier:)) ?? .autoupdatingCurrent)
                .id(languageRaw)
                .task {
                    downloadManager.reconcileOnLaunch()
                    playerController.restoreLastSession()
                }
        }
        .modelContainer(modelContainer)
    }
}
