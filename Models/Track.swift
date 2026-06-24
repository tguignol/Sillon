import Foundation
import SwiftData

@Model
final class Track {
    @Attribute(.unique) var id: String   // "<serverID>:<remoteID>"
    var remoteID: String
    var title: String
    var trackNumber: Int?
    var discNumber: Int?
    var durationSeconds: Double
    /// Codec/conteneur d'origine (ex: "flac", "mp3", "alac"). Sert à informer l'utilisateur
    /// qu'aucun transcodage n'aura lieu, conformément à la contrainte "pas de transcodage".
    var format: String?
    var bitrate: Int?
    var dateAdded: Date?

    var isFavorite: Bool = false
    var favoriteDate: Date?

    /// Dénormalisé pour les morceaux de compilations / artistes multiples sur un même album.
    var artistNameSnapshot: String?

    var downloadStatus: DownloadStatus = DownloadStatus.notDownloaded
    /// Chemin du fichier local une fois téléchargé (relatif au dossier de l'app, voir Docs/ARCHITECTURE.md
    /// pour la différence de stockage iOS / macOS). Nil si non téléchargé.
    var localFileURLString: String?

    var album: Album?

    /// Référence directe au serveur d'origine, à sens unique — même logique que `Album.server`.
    var server: ServerAccount?

    init(serverID: UUID, remoteID: String, title: String, durationSeconds: Double) {
        self.id = Self.makeID(serverID: serverID, remoteID: remoteID)
        self.remoteID = remoteID
        self.title = title
        self.durationSeconds = durationSeconds
    }

    static func makeID(serverID: UUID, remoteID: String) -> String {
        "\(serverID.uuidString):\(remoteID)"
    }

    var isAvailableOffline: Bool {
        downloadStatus == .downloaded && localFileURLString != nil
    }
}
