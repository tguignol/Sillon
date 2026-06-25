import SwiftUI
import SwiftData

@main
struct SillonApp: App {
    let modelContainer: ModelContainer

    init() {
        modelContainer = SillonSchema.makeContainer()
    }

    /// Loader de pochettes partagé par toute l'app (cache des providers authentifiés + des URLs résolues).
    @State private var artworkLoader = ArtworkLoader()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.artworkLoader, artworkLoader)
                // Le système de design est sombre par nature (cf. Docs/DESIGN_SYSTEM.md : fond noir,
                // texte ivoire, accents cuivre/teal). On impose donc l'apparence sombre de l'app
                // (uniquement l'app — pas le réglage clair/sombre du système).
                .preferredColorScheme(.dark)
        }
        .modelContainer(modelContainer)
    }
}
