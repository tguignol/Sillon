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
        _downloadManager = State(initialValue: DownloadManager(container: container))
    }

    /// Loader de pochettes partagé par toute l'app (cache des providers authentifiés + des URLs résolues).
    @State private var artworkLoader = ArtworkLoader()

    /// Gestionnaire de téléchargements partagé (session URLSession de fond).
    @State private var downloadManager: DownloadManager

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.artworkLoader, artworkLoader)
                .environment(\.downloadManager, downloadManager)
                // Le système de design est sombre par nature (cf. Docs/DESIGN_SYSTEM.md : fond noir,
                // texte ivoire, accents cuivre/teal). On impose donc l'apparence sombre de l'app
                // (uniquement l'app — pas le réglage clair/sombre du système).
                .preferredColorScheme(.dark)
                .task { downloadManager.reconcileOnLaunch() }
        }
        .modelContainer(modelContainer)
    }
}
