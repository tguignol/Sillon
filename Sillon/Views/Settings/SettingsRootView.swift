import SwiftUI
import SwiftData

/// Racine de l'onglet Réglages. Les sections Égaliseur et préférences générales seront ajoutées
/// aux commits "Lecteur + Égaliseur" et suivants — ce commit n'introduit que la gestion des serveurs.
struct SettingsRootView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ServerListView()
                } label: {
                    Label("Serveurs", systemImage: "server.rack")
                }
                NavigationLink {
                    DownloadsView()
                } label: {
                    Label("Téléchargements", systemImage: "arrow.down.circle")
                }
                NavigationLink {
                    EQView()
                } label: {
                    Label("Égaliseur", systemImage: "slider.vertical.3")
                }
                NavigationLink {
                    PlaybackSettingsView()
                } label: {
                    Label("Lecture", systemImage: "play.circle")
                }
            }
            .navigationTitle("Réglages")
        }
    }
}

#Preview {
    SettingsRootView()
        .modelContainer(SillonSchema.makeContainer(inMemory: true))
}
