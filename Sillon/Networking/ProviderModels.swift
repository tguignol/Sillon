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
