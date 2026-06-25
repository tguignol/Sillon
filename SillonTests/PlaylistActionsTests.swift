import Testing
import Foundation
import SwiftData
@testable import Sillon

@MainActor
struct PlaylistActionsTests {

    private func makeContext() -> ModelContext {
        let context = ModelContext(SillonSchema.makeContainer(inMemory: true))
        context.autosaveEnabled = false
        return context
    }

    private func makeTracks(_ count: Int, in context: ModelContext) -> [Track] {
        let server = ServerAccount(name: "S", type: .subsonic)
        context.insert(server)
        return (0..<count).map { i in
            let t = Track(serverID: server.id, remoteID: "t\(i)", title: "Titre \(i)", durationSeconds: 100)
            t.server = server
            context.insert(t)
            return t
        }
    }

    @Test func addAppendsWithContiguousPositions() {
        let context = makeContext()
        let tracks = makeTracks(3, in: context)
        let playlist = PlaylistActions.create(name: "P", context: context)

        PlaylistActions.add(tracks, to: playlist, context: context)

        let ordered = playlist.items.sorted { $0.position < $1.position }
        #expect(ordered.map(\.position) == [0, 1, 2])
        #expect(ordered.compactMap { $0.track?.title } == ["Titre 0", "Titre 1", "Titre 2"])
    }

    @Test func moveRewritesPositionsContiguously() {
        let context = makeContext()
        let tracks = makeTracks(3, in: context)
        let playlist = PlaylistActions.create(name: "P", context: context)
        PlaylistActions.add(tracks, to: playlist, context: context)

        let ordered = playlist.items.sorted { $0.position < $1.position }
        // Déplace le 1er élément en dernier.
        PlaylistActions.move(ordered, from: IndexSet(integer: 0), to: 3, playlist: playlist, context: context)

        let reordered = playlist.items.sorted { $0.position < $1.position }
        #expect(reordered.map(\.position) == [0, 1, 2])
        #expect(reordered.compactMap { $0.track?.title } == ["Titre 1", "Titre 2", "Titre 0"])
    }

    @Test func removeDropsItem() {
        let context = makeContext()
        let tracks = makeTracks(3, in: context)
        let playlist = PlaylistActions.create(name: "P", context: context)
        PlaylistActions.add(tracks, to: playlist, context: context)

        let ordered = playlist.items.sorted { $0.position < $1.position }
        PlaylistActions.removeItems(at: IndexSet(integer: 1), from: ordered, playlist: playlist, context: context)

        #expect(playlist.items.count == 2)
        #expect(playlist.items.compactMap { $0.track?.title }.sorted() == ["Titre 0", "Titre 2"])
        // Positions réindexées de façon contiguë (pas de trou) après suppression.
        #expect(playlist.items.map(\.position).sorted() == [0, 1])
    }
}
