import Foundation
import SwiftData

@Observable
final class AddServerViewModel {
    enum ConnectionTestStatus: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    enum SubsonicAuthMode: String, CaseIterable, Identifiable, Hashable {
        case password = "Mot de passe"
        case tokenAndSalt = "Jeton + sel"
        var id: String { rawValue }
    }

    /// Identifiant définitif du serveur en cours de création, généré une seule fois pour toute la
    /// durée de vie du formulaire. Utilisé à la fois pour le test de connexion et l'enregistrement
    /// final, afin d'éviter une double manipulation du Keychain (cf. Docs/DECISIONS.md).
    let draftServerID = UUID()

    var serverType: ServerType = .jellyfin {
        didSet { invalidateConnectionTest() }
    }
    var name: String = ""
    var baseURLString: String = "" {
        didSet { invalidateConnectionTest() }
    }
    var username: String = "" {
        didSet { invalidateConnectionTest() }
    }
    var password: String = "" {
        didSet { invalidateConnectionTest() }
    }

    var subsonicAuthMode: SubsonicAuthMode = .password {
        didSet { invalidateConnectionTest() }
    }
    var subsonicToken: String = "" {
        didSet { invalidateConnectionTest() }
    }
    var subsonicSalt: String = "" {
        didSet { invalidateConnectionTest() }
    }

    var localFolderBookmark: Data?
    var localFolderDisplayName: String?

    var connectionTest: ConnectionTestStatus = .idle
    var isTesting: Bool { connectionTest == .testing }

    /// La spécification demande une "validation/test de connexion avant sauvegarde" : on l'applique
    /// littéralement en n'activant le bouton Enregistrer qu'après un test réussi (cf. `AddServerView`),
    /// et toute modification d'un champ pertinent invalide ce test pour éviter d'enregistrer des
    /// identifiants jamais vérifiés.
    var isConnectionVerified: Bool {
        if case .success = connectionTest { return true }
        return false
    }

    private var hasPersistedCredentials = false

    private func invalidateConnectionTest() {
        guard connectionTest != .idle else { return }
        connectionTest = .idle
        hasPersistedCredentials = false
    }

    var canSave: Bool {
        switch serverType {
        case .jellyfin:
            return !baseURLString.isEmpty && !username.isEmpty && !password.isEmpty
        case .subsonic:
            switch subsonicAuthMode {
            case .password:
                return !baseURLString.isEmpty && !username.isEmpty && !password.isEmpty
            case .tokenAndSalt:
                return !baseURLString.isEmpty && !username.isEmpty && !subsonicToken.isEmpty && !subsonicSalt.isEmpty
            }
        case .local:
            return localFolderBookmark != nil
        }
    }

    func didPickLocalFolder(_ url: URL) {
        invalidateConnectionTest()
        guard url.startAccessingSecurityScopedResource() else {
            connectionTest = .failure("Accès au dossier refusé par le système.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            #if os(macOS)
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            #else
            let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            #endif
            localFolderBookmark = bookmark
            localFolderDisplayName = url.lastPathComponent
            if name.isEmpty { name = url.lastPathComponent }
        } catch {
            connectionTest = .failure("Impossible de mémoriser l'accès au dossier : \(error.localizedDescription)")
        }
    }

    @MainActor
    func testConnection() async {
        connectionTest = .testing
        do {
            try persistDraftCredentials()
            let provider = try makeDraftProvider()
            let session = try await provider.authenticate()
            if serverType == .local {
                connectionTest = .success("Accès au dossier confirmé (\(session.serverDisplayName ?? "dossier")).")
            } else {
                connectionTest = .success(session.serverVersion.map { "Connexion réussie (version \($0))." } ?? "Connexion réussie.")
            }
        } catch {
            connectionTest = .failure((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Garde-fou défensif : ce cas ne devrait jamais se produire via l'UI (le bouton Enregistrer est
    /// désactivé tant que `isConnectionVerified` est faux), mais on préfère échouer explicitement
    /// plutôt que d'enregistrer un serveur dont la connexion n'a jamais été vérifiée.
    private struct ConnectionNotVerifiedError: LocalizedError {
        var errorDescription: String? { "La connexion doit être testée avec succès avant l'enregistrement." }
    }

    func save(in context: ModelContext) throws {
        guard isConnectionVerified else {
            throw ConnectionNotVerifiedError()
        }
        if !hasPersistedCredentials {
            try persistDraftCredentials()
        }
        let displayName = name.isEmpty ? defaultName() : name
        let account = ServerAccount(id: draftServerID, name: displayName, type: serverType, baseURLString: baseURLString, username: username)
        account.localFolderBookmark = localFolderBookmark
        context.insert(account)
    }

    /// À appeler si l'utilisateur annule le formulaire, pour ne pas laisser de secrets orphelins
    /// en Keychain sous `draftServerID` (cas où `testConnection()` a déjà été appelé).
    func discardDraft() {
        KeychainStore.deleteAll(for: draftServerID)
    }

    private func persistDraftCredentials() throws {
        switch serverType {
        case .jellyfin:
            try KeychainStore.save(password, for: draftServerID, field: .password)
        case .subsonic:
            switch subsonicAuthMode {
            case .password:
                try KeychainStore.save(password, for: draftServerID, field: .password)
            case .tokenAndSalt:
                try KeychainStore.save(subsonicToken, for: draftServerID, field: .apiToken)
                try KeychainStore.save(subsonicSalt, for: draftServerID, field: .subsonicSalt)
            }
        case .local:
            break
        }
        hasPersistedCredentials = true
    }

    private func makeDraftProvider() throws -> any ServerProvider {
        switch serverType {
        case .jellyfin:
            guard let url = URL(string: baseURLString) else { throw ProviderError.invalidURL }
            return JellyfinProvider(serverID: draftServerID, baseURL: url, username: username)
        case .subsonic:
            guard let url = URL(string: baseURLString) else { throw ProviderError.invalidURL }
            return SubsonicProvider(serverID: draftServerID, baseURL: url, username: username)
        case .local:
            return LocalFilesProvider(serverID: draftServerID, folderBookmark: localFolderBookmark)
        }
    }

    private func defaultName() -> String {
        switch serverType {
        case .jellyfin: "Jellyfin"
        case .subsonic: "Navidrome"
        case .local: localFolderDisplayName ?? "Dossier local"
        }
    }
}
