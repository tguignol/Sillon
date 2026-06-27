import Foundation

/// Calcule l'emplacement local d'un morceau téléchargé, en reproduisant l'arborescence serveur :
/// `<racine>/<NomServeur>/<Artiste>/<Album>/<NN - Titre>.<ext>` (cf. brief et Docs/DECISIONS.md #5).
///
/// Racine (cf. Docs/DECISIONS.md #5 et #24) :
/// - **iOS** : dossier *Documents* de l'app (visible dans l'app Fichiers si activé).
/// - **macOS** : *Application Support* de l'app. Le placement littéral dans `~/Music` (prévu par
///   la décision #5) nécessite l'entitlement « Music Folder » et est différé pour ne pas modifier
///   le sandbox/les entitlements en cours de phase ; l'arborescence relative reste identique.
enum DownloadFileLayout {

    /// Dossier racine des téléchargements (créé à la demande par le `DownloadManager`).
    static var baseDirectory: URL {
        let fm = FileManager.default
        #if os(macOS)
        let root = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return root.appendingPathComponent("Sillon/Downloads", isDirectory: true)
        #else
        let root = (try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return root.appendingPathComponent("Downloads", isDirectory: true)
        #endif
    }

    /// Destination finale d'un morceau, dossiers intermédiaires compris (non créés ici).
    static func destination(for track: Track) -> URL {
        let server = sanitize(track.server?.name ?? "Serveur")
        let artist = sanitize(track.album?.artist?.name ?? track.artistNameSnapshot ?? "Artiste inconnu")
        let album = sanitize(track.album?.title ?? "Album inconnu")
        // Trim avant de décider : un format ne contenant que des espaces ne doit pas devenir l'extension.
        let trimmedFormat = track.format?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ext = (trimmedFormat?.isEmpty == false) ? trimmedFormat! : "audio"

        let stem: String
        if let number = track.trackNumber {
            stem = sanitize(String(format: "%02d - %@", number, track.title))
        } else {
            stem = sanitize(track.title)
        }

        return baseDirectory
            .appendingPathComponent(server, isDirectory: true)
            .appendingPathComponent(artist, isDirectory: true)
            .appendingPathComponent(album, isDirectory: true)
            .appendingPathComponent("\(stem).\(ext)", isDirectory: false)
    }

    /// Résout un chemin de fichier téléchargé MÉMORISÉ vers une URL valide sur la racine COURANTE.
    /// Indispensable car le conteneur de l'app peut changer d'emplacement après une mise à jour /
    /// réinstallation iOS : un chemin absolu mémorisé devient alors périmé (téléchargements « perdus »).
    /// Si le chemin existe tel quel, on le garde ; sinon on reconstruit à partir du suffixe relatif
    /// (« …/Downloads/<serveur>/<artiste>/<album>/<fichier> ») sur la racine actuelle.
    static func resolve(storedPath: String) -> URL {
        if FileManager.default.fileExists(atPath: storedPath) { return URL(fileURLWithPath: storedPath) }
        if let range = storedPath.range(of: "/Downloads/") {
            return baseDirectory.appendingPathComponent(String(storedPath[range.upperBound...]))
        }
        return URL(fileURLWithPath: storedPath)
    }

    /// Nettoie un composant de chemin : remplace les caractères interdits, borne la longueur.
    static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
        let bounded = String(cleaned.prefix(120))
        return bounded.isEmpty ? "_" : bounded
    }
}
