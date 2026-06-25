import Testing
import Foundation
import SwiftData
@testable import Sillon

/// Tests d'intégration **réseau** contre de vrais serveurs (Jellyfin, Navidrome/Subsonic).
///
/// Sécurité : aucun identifiant n'est codé en dur. Les tests lisent l'URL / le login / le mot de
/// passe depuis des variables d'environnement (passées via `TEST_RUNNER_…` au lancement xcodebuild)
/// et **se désactivent automatiquement** si elles sont absentes — ce fichier est donc sans secret et
/// inoffensif en CI. Le mot de passe est écrit dans le Keychain le temps du test puis supprimé.
///
/// Ils valident le pipeline réel de bout en bout : authenticate → fetchLibrary → upsert SwiftData
/// (via `LibrarySyncService`) → persistance vérifiée.
@MainActor
struct ServerIntegrationTests {

    nonisolated private static func env(_ key: String) -> String? {
        let value = ProcessInfo.processInfo.environment[key]
        return (value?.isEmpty == false) ? value : nil
    }

    nonisolated private static var jellyfinConfigured: Bool {
        env("SILLON_JF_URL") != nil && env("SILLON_JF_USER") != nil && env("SILLON_JF_PW") != nil
    }
    nonisolated private static var navidromeConfigured: Bool {
        env("SILLON_ND_URL") != nil && env("SILLON_ND_USER") != nil && env("SILLON_ND_PW") != nil
    }

    private func makeContext() -> ModelContext {
        let context = ModelContext(SillonSchema.makeContainer(inMemory: true))
        context.autosaveEnabled = false
        return context
    }

    /// Exécute une synchro réelle et renvoie les compteurs persistés, après nettoyage du Keychain.
    private func runRealSync(type: ServerType, urlKey: String, userKey: String, pwKey: String) async throws {
        let url = try #require(URL(string: Self.env(urlKey)!))
        let user = Self.env(userKey)!
        let password = Self.env(pwKey)!

        let serverID = UUID()
        try KeychainStore.save(password, for: serverID, field: .password)
        defer { KeychainStore.deleteAll(for: serverID) }

        let context = makeContext()
        let server = ServerAccount(id: serverID, name: "Intégration", type: type,
                                   baseURLString: url.absoluteString, username: user)
        context.insert(server)

        let provider = try ServerProviderFactory.makeProvider(for: server)

        // Auth seule d'abord, pour un message d'échec clair si les identifiants sont refusés.
        let session = try await provider.authenticate()
        #expect(session.userID != nil || session.token != nil, "Authentification sans session exploitable")

        // Synchro complète + persistance (le moteur ré-authentifie et appelle fetchLibrary).
        try await LibrarySyncService.synchronize(server, using: provider, context: context)

        let artists = try context.fetch(FetchDescriptor<Artist>()).count
        let albums = try context.fetch(FetchDescriptor<Album>()).count
        let tracks = try context.fetch(FetchDescriptor<Track>()).count

        // Un serveur de musique réel doit renvoyer au moins quelques morceaux.
        #expect(tracks > 0, "\(type.rawValue) — artistes:\(artists) albums:\(albums) titres:\(tracks)")
        #expect(server.lastFullSyncDate != nil)
        #expect(server.syncCursor != nil)

        print("SILLON_INTEGRATION \(type.rawValue) — persistés : \(artists) artistes, \(albums) albums, \(tracks) titres")
    }

    @Test(.enabled(if: ServerIntegrationTests.jellyfinConfigured))
    func jellyfinRealSync() async throws {
        try await runRealSync(type: .jellyfin, urlKey: "SILLON_JF_URL", userKey: "SILLON_JF_USER", pwKey: "SILLON_JF_PW")
    }

    @Test(.enabled(if: ServerIntegrationTests.navidromeConfigured))
    func navidromeRealSync() async throws {
        try await runRealSync(type: .subsonic, urlKey: "SILLON_ND_URL", userKey: "SILLON_ND_USER", pwKey: "SILLON_ND_PW")
    }
}
