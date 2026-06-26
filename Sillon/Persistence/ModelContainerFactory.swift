import SwiftData

/// Schéma SwiftData centralisé : toute évolution de modèle (ajout de propriété, etc.)
/// doit être reflétée ici si elle nécessite une migration explicite plus tard.
enum SillonSchema {
    static var models: [any PersistentModel.Type] {
        [
            ServerAccount.self,
            Artist.self,
            Album.self,
            Track.self,
            Playlist.self,
            PlaylistItem.self,
            DownloadTask.self,
            EQSettings.self,
            EQPreset.self
        ]
    }

    /// `inMemory: true` est utilisé par les Previews SwiftUI et les futurs tests,
    /// pour ne jamais toucher au store persistant réel pendant le développement.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: Schema(models), configurations: [configuration])
        } catch {
            // Un échec ici signifie un schéma incohérent ou un store corrompu : il n'y a pas
            // de stratégie de repli raisonnable, on préfère un crash explicite au lancement
            // plutôt qu'un état silencieusement incorrect.
            fatalError("Impossible de créer le ModelContainer SwiftData : \(error)")
        }
    }
}
