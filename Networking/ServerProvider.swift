import Foundation

/// Contrat commun à toutes les sources audio : Jellyfin, Navidrome/Subsonic, fichiers locaux.
///
/// Décision documentée : déclaré comme protocole d'acteur (`Actor`) plutôt que protocole classique.
/// Chaque provider gère un état mutable sensible à la concurrence (jeton de session, éventuellement
/// un cache de réponses) et peut être sollicité simultanément par la synchro, la lecture en streaming
/// et le gestionnaire de téléchargements. Les `actor` Swift apportent cette sécurité sans verrous manuels,
/// et s'alignent avec le mode de concurrence strict probable des nouveaux projets ciblant iOS 26/macOS 26.
/// Les implémentations concrètes (commit suivant) seront donc déclarées `actor JellyfinProvider: ServerProvider`, etc.
protocol ServerProvider: Actor {
    /// Authentifie le compte et retourne une session (jeton, version serveur...).
    /// Pour `.local`, correspond à la résolution du bookmark de dossier (pas de réseau).
    func authenticate() async throws -> ProviderSession

    /// Récupère l'intégralité de la bibliothèque. Utilisé uniquement à la 1ère synchronisation
    /// (cf. `ServerAccount.hasCompletedInitialSync`), conformément à la contrainte
    /// "scan delta, pas full re-scan sauf 1ère fois".
    func fetchLibrary() async throws -> LibrarySnapshot

    /// Synchronisation incrémentale depuis le dernier curseur connu (`ServerAccount.syncCursor`).
    /// `since: nil` équivaut à un appel jamais effectué auparavant (l'appelant choisit alors
    /// d'utiliser `fetchLibrary()` à la place plutôt que `syncDelta(since: nil)`).
    func syncDelta(since syncCursor: String?) async throws -> SyncDelta

    /// URL de lecture en streaming, format original (sans transcodage) pour le morceau donné.
    func streamURL(for trackRemoteID: String) async throws -> URL

    /// URL à utiliser pour un téléchargement complet. Peut différer de `streamURL` :
    /// par ex. Subsonic expose un endpoint `download` dédié, garanti sans transcodage,
    /// distinct de `stream` qui pourrait être configuré côté serveur pour transcoder par défaut.
    func downloadURL(for trackRemoteID: String) async throws -> URL

    /// URL de la pochette pour un artiste/album/morceau, selon l'identifiant distant transmis.
    /// `preferredSize`, quand le serveur le permet, demande une taille de vignette adaptée à l'UI.
    func coverArtURL(for remoteID: String, preferredSize: Int?) async throws -> URL?

    /// Recherche unifiée (artistes + albums + morceaux) côté serveur.
    func searchAll(query: String) async throws -> SearchResults
}
