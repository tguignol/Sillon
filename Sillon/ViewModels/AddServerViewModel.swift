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

    /// Avertissement (non bloquant) si l'adresse serveur est en **http** (non chiffré) : les identifiants
    /// — token/sel Subsonic dans l'URL, mot de passe à l'authentification — et le flux audio transitent
    /// alors en clair sur le réseau. Non bloquant car un serveur local en http reste un cas légitime.
    var insecureSchemeWarning: String? {
        guard serverType != .local else { return nil }
        guard let scheme = URL(string: baseURLString.trimmingCharacters(in: .whitespaces))?.scheme?.lowercased() else { return nil }
        guard scheme == "http" else { return nil }
        return LanguageManager.string("Adresse en http (non chiffré) : vos identifiants et le flux transitent en clair sur le réseau. Préférez https si votre serveur le permet.")
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
            connectionTest = .failure(LanguageManager.string("Accès au dossier refusé par le système."))
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
            connectionTest = .failure(LanguageManager.string("Impossible de mémoriser l'accès au dossier : %@", error.localizedDescription))
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
                connectionTest = .success(LanguageManager.string("Accès au dossier confirmé (%@).", session.serverDisplayName ?? LanguageManager.string("dossier")))
            } else {
                connectionTest = .success(session.serverVersion.map { LanguageManager.string("Connexion réussie (version %@).", $0) } ?? LanguageManager.string("Connexion réussie."))
            }
        } catch {
            connectionTest = .failure((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Garde-fou défensif : ce cas ne devrait jamais se produire via l'UI (le bouton Enregistrer est
    /// désactivé tant que `isConnectionVerified` est faux), mais on préfère échouer explicitement
    /// plutôt que d'enregistrer un serveur dont la connexion n'a jamais été vérifiée.
    private struct ConnectionNotVerifiedError: LocalizedError {
        var errorDescription: String? { LanguageManager.string("La connexion doit être testée avec succès avant l'enregistrement.") }
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
        // Priorité définie dès la création (sinon elle ne le serait qu'à l'ouverture de Réglages →
        // Serveurs) : le nouveau serveur arrive en dernier (priorité la plus basse) et ne collisionne
        // pas avec un sortOrder=0 placé manuellement, ce qui préserve l'ordre choisi par l'utilisateur.
        let maxOrder = ((try? context.fetch(FetchDescriptor<ServerAccount>())) ?? []).map(\.sortOrder).max()
        account.sortOrder = (maxOrder ?? -1) + 1
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
        case .local: localFolderDisplayName ?? LanguageManager.string("Dossier local")
        }
    }
}
