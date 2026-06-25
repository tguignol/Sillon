import Testing
import Foundation
import SwiftData
@testable import Sillon

@MainActor
struct PlayerQueueTests {

    private func makePlayer() -> (PlayerController, [Track]) {
        let container = SillonSchema.makeContainer(inMemory: true)
        let context = container.mainContext
        // baseURL vide -> la résolution d'URL échoue proprement (pas de réseau en test).
        let server = ServerAccount(name: "S", type: .subsonic)
        context.insert(server)
        let tracks = (0..<5).map { i -> Track in
            let t = Track(serverID: server.id, remoteID: "t\(i)", title: "T\(i)", durationSeconds: 10)
            t.server = server
            context.insert(t)
            return t
        }
        return (PlayerController(container: container), tracks)
    }

    @Test func shuffleKeepsCurrentFirstThenRestoresOrder() {
        let (player, tracks) = makePlayer()
        player.play(queue: tracks, startAt: 2)
        #expect(player.currentTrack?.id == tracks[2].id)

        player.toggleShuffle()
        #expect(player.isShuffled)
        #expect(player.queue.count == 5)
        #expect(player.currentTrack?.id == tracks[2].id)   // le morceau en cours reste

        player.toggleShuffle()
        #expect(!player.isShuffled)
        #expect(player.queue.map(\.id) == tracks.map(\.id))   // ordre d'origine restauré
        #expect(player.currentTrack?.id == tracks[2].id)
    }

    @Test func repeatModeCyclesOffAllOne() {
        let (player, _) = makePlayer()
        #expect(player.repeatMode == .off)
        player.cycleRepeatMode(); #expect(player.repeatMode == .all)
        player.cycleRepeatMode(); #expect(player.repeatMode == .one)
        player.cycleRepeatMode(); #expect(player.repeatMode == .off)
    }

    @Test func moveQueueKeepsCurrentTrack() {
        let (player, tracks) = makePlayer()
        player.play(queue: tracks, startAt: 0)   // current = T0
        player.moveQueue(from: IndexSet(integer: 0), to: 3)   // T0 déplacé en position 2
        #expect(player.currentTrack?.id == tracks[0].id)       // suit son morceau
        #expect(player.queue.count == 5)
    }
}
