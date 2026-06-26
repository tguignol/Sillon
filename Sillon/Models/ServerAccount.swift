import Foundation
import SwiftData

/// Type de serveur audio connecté.
enum ServerType: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case jellyfin
    case subsonic   // Navidrome ou tout serveur compatible API Subsonic / OpenSubsonic
    case local      // Dossier local (macOS) ou dossier importé (iOS, via UIDocumentPicker)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jellyfin: "Jellyfin"
        case .subsonic: "Navidrome / Subsonic"
        case .local: "Fichiers locaux"
        }
    }

    var systemImageName: String {
        switch self {
        case .jellyfin: "server.rack"
        case .subsonic: "antenna.radiowaves.left.and.right"
        case .local: "folder.fill"
        }
    }
}

/// Compte serveur configuré par l'utilisateur.
///
/// IMPORTANT — sécurité : aucun secret (mot de passe, jeton, sel Subsonic) n'est stocké ici.
/// Ces valeurs vivent exclusivement dans le Keychain (voir `KeychainStore`), indexées par `id`.
/// Ce modèle ne conserve que ce qui est nécessaire pour reconstruire une connexion et afficher l'UI.
@Model
final class ServerAccount {
    @Attribute(.unique) var id: UUID
    var name: String
    var type: ServerType
    var baseURLString: String
    var username: String

    /// Serveur actif : ses contenus apparaissent dans la bibliothèque (accueil, grilles, recherche…).
    /// Le désactiver les masque SANS supprimer — réactivation instantanée, sans re-synchronisation.
    /// Migration légère (valeur par défaut, aucun MigrationPlan requis).
    var isActive: Bool = true

    /// Uniquement pour `.local` : bookmark de sécurité (App Sandbox / iOS) vers le dossier choisi par l'utilisateur.
    /// Permet de retrouver l'accès au dossier après redémarrage sans nouvelle demande de permission.
    var localFolderBookmark: Data?

    var lastDeltaSyncDate: Date?
    var lastFullSyncDate: Date?
    var createdAt: Date

    /// Renseigné après la première authentification réussie (ex: "10.10.7" pour Jellyfin, "1.16.1" pour Subsonic).
    /// Permet aux providers d'adapter leurs requêtes aux capacités réelles du serveur.
    var negotiatedAPIVersion: String?

    /// Jeton de curseur utilisé par `syncDelta` (ex: horodatage ISO8601 ou curseur opaque du serveur).
    /// Conservé ici plutôt que recalculé, pour permettre une synchro delta même après fermeture de l'app.
    var syncCursor: String?

    @Relationship(deleteRule: .cascade, inverse: \Artist.server)
    var artists: [Artist] = []

    @Relationship(deleteRule: .cascade, inverse: \Playlist.server)
    var playlists: [Playlist] = []

    init(name: String, type: ServerType, baseURLString: String = "", username: String = "") {
        self.id = UUID()
        self.name = name
        self.type = type
        self.baseURLString = baseURLString
        self.username = username
        self.createdAt = .now
    }

    /// Variante utilisée par `AddServerViewModel` : le formulaire génère un UUID "brouillon" dès
    /// son ouverture pour pouvoir tester la connexion (et donc déjà écrire des secrets en Keychain
    /// sous cet identifiant) avant l'enregistrement définitif. On réutilise ce même UUID ici plutôt
    /// que d'en générer un nouveau, pour ne pas avoir à déplacer les entrées Keychain déjà créées.
    init(id: UUID, name: String, type: ServerType, baseURLString: String = "", username: String = "") {
        self.id = id
        self.name = name
        self.type = type
        self.baseURLString = baseURLString
        self.username = username
        self.createdAt = .now
    }

    var baseURL: URL? { URL(string: baseURLString) }

    /// Vrai si une première synchronisation complète a déjà eu lieu (sert à décider full scan vs delta).
    var hasCompletedInitialSync: Bool { lastFullSyncDate != nil }
}
