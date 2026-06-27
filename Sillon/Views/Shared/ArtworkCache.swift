import Foundation
import CryptoKit

/// Cache disque persistant des pochettes. Les images sont téléchargées pendant la synchronisation
/// (cf. `LibrarySyncService`) puis relues localement → affichage instantané, sans requête réseau par
/// cellule. Une image par couple (serveur, chemin distant) à une résolution canonique ; l'affichage
/// downscale au besoin. Le dossier vit dans `Caches/` (purgé par le système si l'espace manque ; il
/// sera reconstitué à la prochaine synchro ou au premier affichage).
actor ArtworkCache {
    static let shared = ArtworkCache()

    /// Résolution stockée (px). Couvre les cartes (≤ 360) et le lecteur (600) ; on stocke une seule
    /// taille pour maximiser les réutilisations entre écrans.
    static let canonicalSize = 600

    private let directory: URL
    private let fileManager = FileManager.default

    init() {
        // `FileManager.default` en local : ne pas référencer la propriété isolée `fileManager` depuis
        // cet init non isolé (interdit en mode Swift 6). La propriété reste pour les méthodes isolées.
        let fm = FileManager.default
        let caches = (try? fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        directory = caches.appendingPathComponent("Artwork", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Nom de fichier déterministe et sûr (SHA-256 de « serveur|chemin »).
    private func fileURL(serverID: UUID, path: String) -> URL {
        let digest = SHA256.hash(data: Data("\(serverID.uuidString)|\(path)".utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("img")
    }

    /// URL fichier locale si la pochette est déjà en cache, sinon `nil`.
    func existingFile(serverID: UUID, path: String) -> URL? {
        let url = fileURL(serverID: serverID, path: path)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Écrit les données image en cache et renvoie l'URL fichier locale.
    @discardableResult
    func store(_ data: Data, serverID: UUID, path: String) -> URL {
        let url = fileURL(serverID: serverID, path: path)
        try? data.write(to: url, options: .atomic)
        return url
    }
}
