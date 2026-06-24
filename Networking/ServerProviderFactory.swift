import Foundation

/// Instancie l'implémentation `ServerProvider` adaptée à un `ServerAccount` donné.
/// Point d'entrée unique utilisé par l'UI et, plus tard, par le moteur de synchronisation —
/// évite de dupliquer ce `switch` à chaque endroit qui a besoin de parler à un serveur.
enum ServerProviderFactory {
    static func makeProvider(for server: ServerAccount) throws -> any ServerProvider {
        switch server.type {
        case .jellyfin:
            guard let baseURL = server.baseURL else { throw ProviderError.invalidURL }
            return JellyfinProvider(serverID: server.id, baseURL: baseURL, username: server.username)
        case .subsonic:
            guard let baseURL = server.baseURL else { throw ProviderError.invalidURL }
            return SubsonicProvider(serverID: server.id, baseURL: baseURL, username: server.username)
        case .local:
            return LocalFilesProvider(serverID: server.id, folderBookmark: server.localFolderBookmark)
        }
    }
}
