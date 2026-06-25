import Foundation
import SwiftData

@MainActor
@Observable
final class ServerListViewModel {
    enum SyncState: Equatable {
        case idle
        case syncing(LibrarySyncService.Progress)
        case failed(String)
    }

    private(set) var syncStates: [UUID: SyncState] = [:]

    func syncState(for serverID: UUID) -> SyncState {
        syncStates[serverID] ?? .idle
    }

    /// Lance la synchronisation réelle : le moteur (`LibrarySyncService`) authentifie, récupère
    /// la bibliothèque (scan complet la 1ʳᵉ fois, sinon delta) et **persiste** les résultats en
    /// SwiftData. La progression est remontée en continu pour alimenter la barre de l'UI.
    func synchronize(_ server: ServerAccount, context: ModelContext) async {
        syncStates[server.id] = .syncing(.init(phase: .authenticating))
        do {
            try await LibrarySyncService.synchronize(server, context: context) { progress in
                self.syncStates[server.id] = .syncing(progress)
            }
            syncStates[server.id] = .idle
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            syncStates[server.id] = .failed(message)
        }
    }
}
