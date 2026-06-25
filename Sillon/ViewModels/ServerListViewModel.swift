import Foundation
import SwiftData

@Observable
final class ServerListViewModel {
    enum SyncState: Equatable {
        case idle
        case syncing
        case failed(String)
    }

    private(set) var syncStates: [UUID: SyncState] = [:]

    func syncState(for serverID: UUID) -> SyncState {
        syncStates[serverID] ?? .idle
    }

    @MainActor
    func synchronize(_ server: ServerAccount, context: ModelContext) async {
        syncStates[server.id] = .syncing
        do {
            let provider = try ServerProviderFactory.makeProvider(for: server)
            _ = try await provider.authenticate()

            // NOTE — périmètre de ce commit : on vérifie ici que la connexion fonctionne réellement
            // (authentification + premier appel de bibliothèque) et on met à jour les horodatages.
            // La persistance des résultats (création/mise à jour des Artist/Album/Track SwiftData à
            // partir de LibrarySnapshot/SyncDelta) est implémentée par le moteur de synchro au commit
            // suivant ("Synchronisation + Bibliothèque") — ce commit ne fait donc pas encore apparaître
            // de vrais artistes/albums dans l'onglet Bibliothèque après une synchro réussie.
            if server.hasCompletedInitialSync {
                _ = try await provider.syncDelta(since: server.syncCursor)
            } else {
                _ = try await provider.fetchLibrary()
                server.lastFullSyncDate = .now
            }
            server.lastDeltaSyncDate = .now
            syncStates[server.id] = .idle
        } catch {
            syncStates[server.id] = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
