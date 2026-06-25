import Foundation
import SwiftData

@Model
final class Album {
    @Attribute(.unique) var id: String   // "<serverID>:<remoteID>", même logique que Artist.id
    var remoteID: String
    var title: String
    var year: Int?
    var coverArtRemotePath: String?
    var dateAdded: Date?
    var isFavorite: Bool = false
    var favoriteDate: Date?

    /// Dénormalisé pour affichage rapide (tri, recherche) sans remonter à `artist?.name`,
    /// utile aussi pour les compilations "Various Artists" où `artist` peut être nil.
    var artistNameSnapshot: String?

    var artist: Artist?

    /// Référence directe au serveur d'origine, à sens unique (pas de tableau `albums` côté
    /// `ServerAccount` : les albums sont déjà atteignables via `server.artists.flatMap(\.albums)`).
    /// Conservée ici pour permettre un filtrage/une suppression rapide sans remonter par l'artiste.
    var server: ServerAccount?

    @Relationship(deleteRule: .cascade, inverse: \Track.album)
    var tracks: [Track] = []

    init(serverID: UUID, remoteID: String, title: String) {
        self.id = Self.makeID(serverID: serverID, remoteID: remoteID)
        self.remoteID = remoteID
        self.title = title
    }

    static func makeID(serverID: UUID, remoteID: String) -> String {
        "\(serverID.uuidString):\(remoteID)"
    }
}
