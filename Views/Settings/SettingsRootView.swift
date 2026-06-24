import SwiftUI

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
            }
            .navigationTitle("Réglages")
        }
    }
}

#Preview {
    SettingsRootView()
        .modelContainer(SillonSchema.makeContainer(inMemory: true))
}
