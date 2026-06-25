import Foundation
import SwiftUI
import SwiftData

/// Opérations CRUD + réordonnancement sur les playlists locales. Centralisées ici pour que les vues
/// restent déclaratives et que la logique (positions, horodatage, sauvegarde) soit testable.
@MainActor
enum PlaylistActions {
    @discardableResult
    static func create(name: String, context: ModelContext) -> Playlist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let playlist = Playlist(name: trimmed.isEmpty ? "Nouvelle playlist" : trimmed)
        context.insert(playlist)
        try? context.save()
        return playlist
    }

    static func add(_ tracks: [Track], to playlist: Playlist, context: ModelContext) {
        var position = (playlist.items.map(\.position).max() ?? -1) + 1
        for track in tracks {
            let item = PlaylistItem(track: track, position: position)
            item.playlist = playlist
            context.insert(item)
            position += 1
        }
        playlist.updatedAt = .now
        try? context.save()
    }

    static func delete(_ playlist: Playlist, context: ModelContext) {
        context.delete(playlist)   // cascade -> supprime les PlaylistItem
        try? context.save()
    }

    static func removeItems(at offsets: IndexSet, from ordered: [PlaylistItem], playlist: Playlist, context: ModelContext) {
        for index in offsets where ordered.indices.contains(index) {
            context.delete(ordered[index])
        }
        playlist.updatedAt = .now
        try? context.save()
    }

    /// Réordonne par glisser-déposer : réécrit `position` de façon contiguë selon le nouvel ordre.
    static func move(_ ordered: [PlaylistItem], from source: IndexSet, to destination: Int, playlist: Playlist, context: ModelContext) {
        var items = ordered
        items.move(fromOffsets: source, toOffset: destination)
        for (index, item) in items.enumerated() {
            item.position = index
        }
        playlist.updatedAt = .now
        try? context.save()
    }
}
