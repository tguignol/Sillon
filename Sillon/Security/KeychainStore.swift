import Foundation
import Security

/// Champ stocké en Keychain pour un serveur donné.
enum KeychainField: String {
    case password
    case apiToken       // jeton de session Jellyfin (AccessToken), ou jeton API si l'utilisateur en fournit un
    case subsonicSalt   // sel utilisé pour calculer le token Subsonic (t = md5(password + salt))
}

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return LanguageManager.string("Erreur Keychain (code %d).", status)
        case .encodingFailed:
            return LanguageManager.string("Impossible d'encoder la valeur à stocker.")
        }
    }
}

/// Accès simple au Keychain pour les identifiants des comptes serveurs.
/// Une entrée par (serverID, champ) ; aucun secret ne transite jamais par SwiftData.
struct KeychainStore {
    /// À adapter pour correspondre au bundle identifier réel de l'app une fois le projet créé.
    private static let service = "app.sillon.servercredentials"

    static func save(_ value: String, for serverID: UUID, field: KeychainField) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.encodingFailed }
        let account = accountKey(for: serverID, field: field)

        // On supprime l'entrée existante avant d'écrire, pour éviter errSecDuplicateItem
        // et garantir un comportement "upsert" simple côté appelant.
        SecItemDelete(query(account: account) as CFDictionary)

        var addQuery = query(account: account)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    static func read(for serverID: UUID, field: KeychainField) -> String? {
        let account = accountKey(for: serverID, field: field)
        var readQuery = query(account: account)
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for serverID: UUID, field: KeychainField) {
        let account = accountKey(for: serverID, field: field)
        SecItemDelete(query(account: account) as CFDictionary)
    }

    /// Supprime tous les secrets connus pour un serveur (à appeler quand l'utilisateur supprime le serveur).
    static func deleteAll(for serverID: UUID) {
        for field: KeychainField in [.password, .apiToken, .subsonicSalt] {
            delete(for: serverID, field: field)
        }
    }

    private static func accountKey(for serverID: UUID, field: KeychainField) -> String {
        "\(serverID.uuidString).\(field.rawValue)"
    }

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
