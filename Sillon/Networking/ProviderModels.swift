import Foundation

/// Erreurs communes que peut lever n'importe quelle implémentation de `ServerProvider`.
enum ProviderError: LocalizedError {
    case invalidURL
    case unauthorized
    case unreachable(underlying: Error)
    case unexpectedResponse(statusCode: Int, body: String?)
    case decodingFailed(underlying: Error)
    case unsupportedServerVersion(String)
    case missingCredentials
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "L'adresse du serveur est invalide."
        case .unauthorized:
            return "Identifiants refusés par le serveur."
        case .unreachable(let underlying):
            return "Serveur inaccessible : \(underlying.localizedDescription)"
        case .unexpectedResponse(let code, _):
            return "Réponse inattendue du serveur (code \(code))."
        case .decodingFailed:
            return "Réponse du serveur illisible (format inattendu)."
        case .unsupportedServerVersion(let version):
            return "Version de serveur non prise en charge : \(version)."
        case .missingCredentials:
            return "Identifiants manquants pour ce serveur."
        case .cancelled:
            return "Opération annulée."
        }
    }
}

/// Résultat minimal d'une authentification — suffisant pour construire les requêtes suivantes.
struct ProviderSession: Sendable {
    var serverDisplayName: String?
    var serverVersion: String?
    var userID: String?
    /// Jeton à utiliser pour les requêtes suivantes. L'appelant est responsable de le stocker
    /// dans `KeychainStore` (le provider ne touche jamais lui-même au Keychain).
    var token: String?
}

// MARK: - DTOs légers utilisés pendant la synchronisation, avant conversion en modèles SwiftData.
// Volontairement détachés des `@Model` : un provider ne doit pas dépendre de SwiftData,
// et ces structs `Sendable` peuvent traverser les frontières d'acteurs sans contrainte.

struct RemoteArtist: Sendable, Identifiable, Hashable {
    var id: String   // identifiant distant (remoteID), sans préfixe serveur
    var name: String
    var sortName: String?
    /// Chemin/identifiant relatif de la pochette ; transformé en URL via `coverArtURL(for:preferredSize:)`.
    var coverArtPath: String?
}

struct RemoteAlbum: Sendable, Identifiable, Hashable {
    var id: String
    var artistID: String?
    var artistName: String?
    var title: String
    var year: Int?
    var coverArtPath: String?
    var dateAdded: Date?
    /// ReplayGain album (LECTURE SEULE depuis le serveur). Gain en dB, peak en ratio linéaire.
    /// Renseigné par OpenSubsonic (agrégé depuis le détail album) ; nil pour Jellyfin/legacy.
    /// Défauts `nil` => l'initialiseur memberwise reste rétrocompatible avec les sites existants.
    var albumGain: Double? = nil
    var albumPeak: Double? = nil
}

struct RemoteTrack: Sendable, Identifiable, Hashable {
    var id: String
    var albumID: String?
    var albumTitle: String?
    var artistName: String?
    var title: String
    var trackNumber: Int?
    var discNumber: Int?
    var durationSeconds: Double
    var format: String?
    var bitrate: Int?
    var dateAdded: Date?
    var genre: String? = nil
    /// ReplayGain (LECTURE SEULE depuis le serveur). Gains en dB (déjà prêts à appliquer),
    /// peaks en ratio linéaire (~0..1, peut dépasser 1.0 si le master est clippé). nil = pas de donnée.
    /// Jellyfin ne renseigne que `trackGain` (NormalizationGain) ; OpenSubsonic renseigne tout.
    /// Défauts `nil` => l'initialiseur memberwise reste rétrocompatible avec les sites existants.
    var trackGain: Double? = nil
    var trackPeak: Double? = nil
    var albumGain: Double? = nil
    var albumPeak: Double? = nil
    var fallbackGain: Double? = nil   // dB, repli OpenSubsonic quand le gain du mode choisi est absent
}

struct RemotePlaylist: Sendable, Identifiable, Hashable {
    var id: String
    var name: String
    var trackIDs: [String]
}

/// Bibliothèque complète, utilisée uniquement lors de la 1ère synchronisation (full scan).
struct LibrarySnapshot: Sendable {
    var artists: [RemoteArtist]
    var albums: [RemoteAlbum]
    var tracks: [RemoteTrack]
    var playlists: [RemotePlaylist]
}

/// Résultat d'une synchronisation incrémentale : éléments ajoutés/modifiés et identifiants supprimés.
struct SyncDelta: Sendable {
    var updatedArtists: [RemoteArtist]
    var updatedAlbums: [RemoteAlbum]
    var updatedTracks: [RemoteTrack]
    var updatedPlaylists: [RemotePlaylist]
    var deletedTrackIDs: [String]
    var deletedAlbumIDs: [String]
    var deletedArtistIDs: [String]
    /// Nouveau curseur à conserver (`ServerAccount.syncCursor`) pour le prochain appel à `syncDelta`.
    var newSyncCursor: String?
}

struct SearchResults: Sendable {
    var artists: [RemoteArtist]
    var albums: [RemoteAlbum]
    var tracks: [RemoteTrack]
}

/// Une ligne de paroles. `timeSeconds` est non-nil pour des paroles synchronisées (Jellyfin `Start`
/// en ticks .NET, OpenSubsonic `start` en ms) ; nil pour un vers en texte simple sans horodatage.
struct LyricLine: Sendable, Hashable {
    var timeSeconds: Double?
    var text: String
}

/// Paroles d'un morceau, récupérées À LA DEMANDE (jamais persistées, hors schéma SwiftData).
/// `synced == true` => au moins une ligne porte un `timeSeconds` exploitable pour le défilement.
struct TrackLyrics: Sendable, Hashable {
    var synced: Bool
    var lines: [LyricLine]

    /// Index de la ligne courante = ligne horodatée dont le temps est le plus grand parmi ceux <= `t`.
    /// `nil` avant la première ligne ou si aucune ligne n'est horodatée. Robuste à un ordre non trié
    /// (ne suppose pas les timecodes croissants), sans réordonner l'affichage.
    func activeLineIndex(at t: TimeInterval) -> Int? {
        var bestIndex: Int?
        var bestTime = -Double.infinity
        for (i, line) in lines.enumerated() {
            guard let lt = line.timeSeconds, lt <= t else { continue }
            if lt >= bestTime { bestTime = lt; bestIndex = i }
        }
        return bestIndex
    }
}
