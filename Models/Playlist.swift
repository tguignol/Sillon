import Foundation
import SwiftData

/// Playlist locale à l'app. Peut être indépendante de tout serveur (`server == nil`),
/// ou rattachée à un serveur si l'on choisit plus tard de synchroniser les playlists distantes
/// (hors-périmètre Phase 1 : on crée/gère les playlists uniquement côté app pour l'instant).
@Model
final class Playlist {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    var server: ServerAccount?

    @Relationship(deleteRule: .cascade, inverse: \PlaylistItem.playlist)
    var items: [PlaylistItem] = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Morceaux dans l'ordre d'écoute, en s'appuyant sur `PlaylistItem.position`.
    var orderedTracks: [Track] {
        items.sorted { $0.position < $1.position }.compactMap(\.track)
    }
}

/// Table de liaison Playlist <-> Track, avec une position explicite pour permettre
/// le réordonnancement par glisser-déposer sans dépendre de l'ordre de stockage SwiftData.
@Model
final class PlaylistItem {
    @Attribute(.unique) var id: UUID
    var position: Int

    var track: Track?
    var playlist: Playlist?

    init(track: Track, position: Int) {
        self.id = UUID()
        self.track = track
        self.position = position
    }
}
