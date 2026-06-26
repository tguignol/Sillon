import SwiftUI
import SwiftData

/// Résout les URLs de pochette à la demande, à partir d'un chemin distant stocké
/// (`coverArtRemotePath`) et du serveur d'origine.
///
/// Pourquoi un service dédié plutôt qu'une URL persistée : les URLs de pochette dépendent de l'état
/// d'authentification (Jellyfin embarque `api_key`, Subsonic embarque jeton+sel), qui n'est connu
/// qu'à l'exécution. On garde donc en base le *chemin* distant et on résout l'URL chargeable au
/// moment de l'affichage. Les `ServerProvider` (acteurs) authentifiés sont mis en cache par serveur,
/// et les URLs résolues mises en cache par (serveur, chemin, taille) pour éviter de reconstruire la
/// requête à chaque apparition d'une cellule.
@MainActor
@Observable
final class ArtworkLoader {
    private var providers: [UUID: any ServerProvider] = [:]
    private var urlCache: [String: URL] = [:]

    /// `nonisolated` pour pouvoir servir de valeur par défaut à l'`@Entry` d'environnement
    /// (évalué hors du `MainActor`). N'accède à aucun état isolé : les stockages ont des valeurs
    /// par défaut.
    nonisolated init() {}

    /// Renvoie une URL **fichier locale** vers la pochette en cache disque (affichage instantané).
    /// Cache-first : sert le fichier local s'il existe, sinon résout l'URL distante, télécharge,
    /// range en cache et renvoie le fichier local. `nil` si indisponible (pas de pochette, serveur
    /// local sans image, ou erreur réseau → l'UI affiche son placeholder).
    func localCoverURL(path: String?, server: ServerAccount?) async -> URL? {
        guard let path, !path.isEmpty, let server else { return nil }
        if let cached = await ArtworkCache.shared.existingFile(serverID: server.id, path: path) {
            return cached
        }
        guard let remote = await coverURL(path: path, server: server, size: ArtworkCache.canonicalSize) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: remote)
            return await ArtworkCache.shared.store(data, serverID: server.id, path: path)
        } catch {
            return remote   // repli : laisser AsyncImage retenter le réseau
        }
    }

    /// Renvoie une URL d'image directement chargeable par `AsyncImage`, ou `nil` si indisponible
    /// (pas de pochette, serveur de fichiers locaux, ou erreur réseau → l'UI affiche un placeholder).
    func coverURL(path: String?, server: ServerAccount?, size: Int) async -> URL? {
        guard let path, !path.isEmpty, let server else { return nil }
        let key = "\(server.id.uuidString)|\(path)|\(size)"
        if let cached = urlCache[key] { return cached }
        do {
            let provider = try provider(for: server)
            if let url = try await provider.coverArtURL(for: path, preferredSize: size) {
                urlCache[key] = url
                return url
            }
        } catch {
            // Connexion impossible / non autorisée : on retombe silencieusement sur le placeholder.
        }
        return nil
    }

    private func provider(for server: ServerAccount) throws -> any ServerProvider {
        if let existing = providers[server.id] { return existing }
        let created = try ServerProviderFactory.makeProvider(for: server)
        providers[server.id] = created
        return created
    }
}

extension EnvironmentValues {
    /// Loader partagé injecté à la racine de l'app. La valeur par défaut (utilisée par les Previews)
    /// ne résout jamais d'URL réelle — les pochettes y apparaissent donc en placeholder, ce qui est
    /// exactement le comportement voulu hors connexion serveur.
    @Entry var artworkLoader = ArtworkLoader()
}
