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

    /// Supprime des items (indices dans la liste VISIBLE `ordered`) puis réindexe **tous** les items
    /// restants — visibles ET masqués (serveurs inactifs) — de façon contiguë, en gardant leur ordre.
    /// Réindexer seulement les visibles ferait collisionner leurs positions avec celles des masqués.
    static func removeItems(at offsets: IndexSet, from ordered: [PlaylistItem], playlist: Playlist, context: ModelContext) {
        let removedItems = offsets.compactMap { ordered.indices.contains($0) ? ordered[$0] : nil }
        let removedSet = Set(removedItems.map(ObjectIdentifier.init))
        // Survivants calculés AVANT la suppression (visibles + masqués), triés par position.
        let survivors = playlist.items
            .filter { !removedSet.contains(ObjectIdentifier($0)) }
            .sorted { $0.position < $1.position }
        for item in removedItems { context.delete(item) }
        for (position, item) in survivors.enumerated() { item.position = position }
        playlist.updatedAt = .now
        try? context.save()
    }

    /// Réordonne par glisser-déposer dans la liste VISIBLE, puis réécrit `position` sur **l'ensemble**
    /// des items : les masqués (serveurs inactifs) gardent leur place relative, les visibles suivent le
    /// nouvel ordre. Réindexer seulement les visibles corromprait les positions des masqués.
    static func move(_ ordered: [PlaylistItem], from source: IndexSet, to destination: Int, playlist: Playlist, context: ModelContext) {
        var visible = ordered
        visible.move(fromOffsets: source, toOffset: destination)

        let visibleSet = Set(visible.map(ObjectIdentifier.init))
        let originalOrder = playlist.items.sorted { $0.position < $1.position }
        var newVisible = visible.makeIterator()
        var merged: [PlaylistItem] = []
        for item in originalOrder {
            if visibleSet.contains(ObjectIdentifier(item)) {
                if let next = newVisible.next() { merged.append(next) }   // slot visible → nouvel ordre
            } else {
                merged.append(item)                                       // slot masqué → place conservée
            }
        }
        for (index, item) in merged.enumerated() { item.position = index }
        playlist.updatedAt = .now
        try? context.save()
    }
}
