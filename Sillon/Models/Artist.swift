import Foundation
import SwiftData

/// Artiste, rattaché à un serveur précis.
///
/// `id` est une clé composite "<serverID>:<remoteID>" : deux serveurs différents peuvent réutiliser
/// le même identifiant distant (ex: deux instances Navidrome), il faut donc préfixer par le serveur
/// pour garantir l'unicité globale exigée par `@Attribute(.unique)`.
@Model
final class Artist {
    @Attribute(.unique) var id: String
    var remoteID: String
    var name: String
    var sortName: String
    var coverArtRemotePath: String?
    var dateAdded: Date?
    var isFavorite: Bool = false
    var favoriteDate: Date?

    var server: ServerAccount?

    @Relationship(deleteRule: .cascade, inverse: \Album.artist)
    var albums: [Album] = []

    init(serverID: UUID, remoteID: String, name: String, sortName: String? = nil) {
        self.id = Self.makeID(serverID: serverID, remoteID: remoteID)
        self.remoteID = remoteID
        self.name = name
        self.sortName = sortName ?? name
    }

    static func makeID(serverID: UUID, remoteID: String) -> String {
        "\(serverID.uuidString):\(remoteID)"
    }
}
