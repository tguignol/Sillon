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
        }
        .modelContainer(modelContainer)
    }
}
