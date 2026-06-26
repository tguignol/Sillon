import SwiftUI
import SwiftData

/// Racine de l'onglet Réglages. Les sections Égaliseur et préférences générales seront ajoutées
/// aux commits "Lecteur + Égaliseur" et suivants — ce commit n'introduit que la gestion des serveurs.
struct SettingsRootView: View {
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.sombre.rawValue
    @AppStorage(LanguageManager.storageKey) private var languageRaw = AppLanguage.system.rawValue

    var body: some View {
        NavigationStack {
            List {
                Picker(selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.systemImage).tag(mode.rawValue)
                    }
                } label: {
                    Label("Apparence", systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.menu)

                Picker(selection: Binding(
                    get: { languageRaw },
                    set: { newValue in
                        // On applique la redirection de bundle AVANT que la racine ne se reconstruise
                        // (via son `.id(langue)`), pour que tout le texte s'affiche dans la nouvelle langue.
                        LanguageManager.apply(AppLanguage(rawValue: newValue) ?? .system)
                        languageRaw = newValue
                    }
                )) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                } label: {
                    Label("Langue", systemImage: "globe")
                }
                .pickerStyle(.navigationLink)
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
