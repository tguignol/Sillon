import Foundation
import AVFoundation

/// Implémentation `ServerProvider` pour un dossier local (macOS) ou importé (iOS).
///
/// Pas de réseau ici : "authentifier" consiste à résoudre le bookmark de sécurité et démarrer
/// l'accès au dossier (sandbox). L'identifiant distant (`remoteID`) d'un morceau est directement
/// le chemin du fichier sur disque — il n'y a pas d'identifiant serveur à inventer.
actor LocalFilesProvider: ServerProvider {
    private let serverID: UUID
    private let folderBookmark: Data?
    private let fileManager = FileManager.default
    private var resolvedFolderURL: URL?
    /// Vrai si on détient un accès security-scoped en cours (à relâcher pour ne pas fuir la ressource).
    private var didStartAccess = false

    /// Cache de la dernière bibliothèque construite + sa signature (chemin → date de modif) : évite de
    /// relire les métadonnées AVFoundation de TOUS les fichiers à chaque recherche/radio. Rebâti
    /// uniquement quand l'ensemble des fichiers (ou leurs dates de modif) a changé.
    private var cachedSnapshot: LibrarySnapshot?
    private var cachedSignature: [String: Date]?

    private static let supportedExtensions: Set<String> = ["mp3", "m4a", "flac", "alac", "wav", "aiff", "aif", "ogg"]

    init(serverID: UUID, folderBookmark: Data?) {
        self.serverID = serverID
        self.folderBookmark = folderBookmark
    }

    deinit {
        // Relâche l'accès security-scoped tenu pour la durée de vie du provider (sinon fuite de ressource).
        if didStartAccess { resolvedFolderURL?.stopAccessingSecurityScopedResource() }
    }

    func authenticate() async throws -> ProviderSession {
        guard let bookmark = folderBookmark else { throw ProviderError.missingCredentials }

        var isStale = false
        let url: URL
        do {
            #if os(macOS)
            // Sur macOS (App Sandbox), le bookmark doit être créé/résolu avec `.withSecurityScope`
            // pour conserver l'accès au dossier après redémarrage de l'app.
            url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            #else
            // Sur iOS, `.withSecurityScope` n'existe pas (pas d'App Sandbox de ce type) : un bookmark
            // standard suffit pour un dossier choisi via le sélecteur de documents.
            url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            #endif
        } catch {
            throw ProviderError.unreachable(underlying: error)
        }

        // Si un accès était déjà ouvert (ré-authentification), on le relâche d'abord pour garder les
        // appels start/stop équilibrés (sinon fuite).
        if didStartAccess {
            resolvedFolderURL?.stopAccessingSecurityScopedResource()
            didStartAccess = false
        }
        guard url.startAccessingSecurityScopedResource() else {
            throw ProviderError.unauthorized
        }
        resolvedFolderURL = url
        didStartAccess = true
        return ProviderSession(serverDisplayName: url.lastPathComponent, serverVersion: nil, userID: nil, token: nil)
    }

    func fetchLibrary() async throws -> LibrarySnapshot {
        if resolvedFolderURL == nil { _ = try await authenticate() }
        return try await librarySnapshot()
    }

    func syncDelta(since syncCursor: String?) async throws -> SyncDelta {
        guard let cursorString = syncCursor, let cursorDate = ISO8601DateFormatter().date(from: cursorString) else {
            throw ProviderError.unsupportedServerVersion(
                "syncDelta nécessite un curseur existant ; utilisez fetchLibrary() pour la 1ère synchronisation."
            )
        }
        if resolvedFolderURL == nil { _ = try await authenticate() }

        let allFiles = try enumerateAudioFiles()
        let changedFiles = allFiles.filter { ($0.modificationDate ?? .distantPast) > cursorDate }
        let snapshot = try await buildSnapshot(from: changedFiles)

        // LIMITE DOCUMENTÉE (cohérente avec Jellyfin/Subsonic, par souci de simplicité et de
        // prévisibilité du comportement de syncDelta à travers les trois providers) : cette synchro
        // delta détecte les fichiers ajoutés/modifiés depuis le curseur, mais pas les suppressions —
        // laissées à une réconciliation complète périodique via fetchLibrary (commit "Synchronisation").
        // Note : techniquement détectable ici (l'énumération du disque est peu coûteuse), mais non
        // implémenté pour rester cohérent avec les deux autres providers à ce stade.
        return SyncDelta(
            updatedArtists: snapshot.artists,
            updatedAlbums: snapshot.albums,
            updatedTracks: snapshot.tracks,
            updatedPlaylists: snapshot.playlists,
            deletedTrackIDs: [],
            deletedAlbumIDs: [],
            deletedArtistIDs: [],
            newSyncCursor: ISO8601DateFormatter().string(from: .now)
        )
    }

    func streamURL(for trackRemoteID: String) async throws -> URL {
        // Pour les fichiers locaux, l'identifiant distant EST le chemin du fichier (cf. buildSnapshot) :
        // la lecture se fait directement depuis le disque, sans notion de flux réseau.
        URL(fileURLWithPath: trackRemoteID)
    }

    func downloadURL(for trackRemoteID: String) async throws -> URL {
        // Rien à télécharger : le fichier est déjà local. L'appelant (gestionnaire de téléchargements,
        // commit "Téléchargements") doit traiter ce cas comme un no-op pour les serveurs de type `.local`.
        URL(fileURLWithPath: trackRemoteID)
    }

    func coverArtURL(for remoteID: String, preferredSize: Int?) async throws -> URL? {
        // Pochette embarquée dans les tags, ou fichier "cover.jpg" dans le dossier de l'album :
        // extraction non implémentée dans ce commit. On préfère renvoyer `nil` plutôt qu'inventer
        // un chemin non vérifié ; à ajouter à l'étape "Bibliothèque" si nécessaire.
        nil
    }

    func searchAll(query: String) async throws -> SearchResults {
        if resolvedFolderURL == nil { _ = try await authenticate() }
        let snapshot = try await librarySnapshot()
        let needle = query.lowercased()
        return SearchResults(
            artists: snapshot.artists.filter { $0.name.lowercased().contains(needle) },
            albums: snapshot.albums.filter { $0.title.lowercased().contains(needle) },
            tracks: snapshot.tracks.filter { $0.title.lowercased().contains(needle) }
        )
    }

    func lyrics(forTrackID trackRemoteID: String) async throws -> TrackLyrics? {
        // Les paroles ne sont pas une clé commune AVFoundation : elles vivent dans des tags
        // format-spécifiques (USLT ID3, `©lyr` iTunes...) au format hétérogène et souvent absents.
        // On lit le tag paroles embarqué (texte simple, non synchronisé) s'il existe, sinon nil.
        let asset = AVURLAsset(url: URL(fileURLWithPath: trackRemoteID))
        let identifiers: [AVMetadataIdentifier] = [.iTunesMetadataLyrics, .id3MetadataUnsynchronizedLyric]
        guard let all = try? await asset.load(.metadata) else { return nil }
        for id in identifiers {
            let items = AVMetadataItem.metadataItems(from: all, filteredByIdentifier: id)
            for item in items {
                if let text = try? await item.load(.stringValue), !text.isEmpty {
                    let lines = text.components(separatedBy: .newlines)
                        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        .map { LyricLine(timeSeconds: nil, text: $0) }
                    guard !lines.isEmpty else { return nil }
                    return TrackLyrics(synced: false, lines: lines)
                }
            }
        }
        return nil
    }

    func radioTracks(seedTrackID: String, limit: Int) async throws -> [RemoteTrack] {
        // Pas de notion de « similarité » pour un dossier local : on alimente la radio avec des titres
        // au hasard de la bibliothèque (hors graine), ce qui reste utile pour une écoute en continu.
        if resolvedFolderURL == nil { _ = try await authenticate() }
        let snapshot = try await librarySnapshot()
        return Array(snapshot.tracks.filter { $0.id != seedTrackID }.shuffled().prefix(limit))
    }

    /// Un dossier de fichiers locaux n'a pas de notion de favori côté « serveur » : ensemble vide.
    func serverFavorites() async throws -> RemoteFavorites { .empty }

    // MARK: - Énumération du système de fichiers

    private struct LocalAudioFile {
        let url: URL
        let modificationDate: Date?
    }

    private func enumerateAudioFiles() throws -> [LocalAudioFile] {
        guard let root = resolvedFolderURL else { throw ProviderError.missingCredentials }

        var results: [LocalAudioFile] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return []
        }
        for case let url as URL in enumerator {
            guard Self.supportedExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            results.append(LocalAudioFile(url: url, modificationDate: values.contentModificationDate))
        }
        return results
    }

    /// Bibliothèque complète, depuis le cache si l'ensemble des fichiers n'a pas changé (sinon rebâtie).
    /// Le cache évite la relecture coûteuse des métadonnées à chaque recherche/radio.
    private func librarySnapshot() async throws -> LibrarySnapshot {
        let files = try enumerateAudioFiles()
        let signature = Dictionary(files.map { ($0.url.path, $0.modificationDate ?? .distantPast) },
                                   uniquingKeysWith: { a, _ in a })
        if let cached = cachedSnapshot, cachedSignature == signature {
            return cached
        }
        let built = try await buildSnapshot(from: files)
        cachedSnapshot = built
        cachedSignature = signature
        return built
    }

    // MARK: - Construction de la bibliothèque à partir des fichiers + de leurs métadonnées

    private func buildSnapshot(from files: [LocalAudioFile]) async throws -> LibrarySnapshot {
        var artistsByID: [String: RemoteArtist] = [:]
        var albumsByID: [String: RemoteAlbum] = [:]
        var tracks: [RemoteTrack] = []

        for file in files {
            let metadata = await Self.readMetadata(for: file.url)

            // Repli sur l'arborescence de dossiers (Artiste/Album/Piste) quand les tags sont absents,
            // conformément à l'attente du brief de "reproduire l'arborescence serveur".
            let folderArtistName = file.url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            let folderAlbumName = file.url.deletingLastPathComponent().lastPathComponent

            let artistName = metadata.artist ?? folderArtistName
            let albumTitle = metadata.album ?? folderAlbumName
            let trackTitle = metadata.title ?? file.url.deletingPathExtension().lastPathComponent

            let artistID = "local-artist:\(artistName)"
            let albumID = "local-album:\(artistName)/\(albumTitle)"
            let trackID = file.url.path

            if artistsByID[artistID] == nil {
                artistsByID[artistID] = RemoteArtist(id: artistID, name: artistName, sortName: nil, coverArtPath: nil)
            }
            if albumsByID[albumID] == nil {
                albumsByID[albumID] = RemoteAlbum(
                    id: albumID, artistID: artistID, artistName: artistName, title: albumTitle,
                    year: metadata.year, coverArtPath: nil, dateAdded: file.modificationDate
                )
            }
            tracks.append(RemoteTrack(
                id: trackID, albumID: albumID, albumTitle: albumTitle, artistName: artistName,
                title: trackTitle,
                // LIMITE DOCUMENTÉE : numéro de piste/disque non renseignés pour les fichiers locaux
                // dans ce commit — les métadonnées génériques exposées par AVFoundation
                // (`commonMetadata`) ne couvrent pas ces tags de façon fiable selon le format
                // (notamment FLAC). Amélioration possible via une lecture de tags spécifique par
                // format, à évaluer si besoin plutôt qu'inventée ici.
                trackNumber: nil, discNumber: nil,
                durationSeconds: metadata.durationSeconds,
                format: file.url.pathExtension.lowercased(), bitrate: nil,
                dateAdded: file.modificationDate
            ))
        }

        return LibrarySnapshot(
            artists: Array(artistsByID.values),
            albums: Array(albumsByID.values),
            tracks: tracks,
            playlists: []
        )
    }

    private struct LocalTrackMetadata {
        var title: String?
        var artist: String?
        var album: String?
        var year: Int?
        var durationSeconds: Double
    }

    private static func readMetadata(for url: URL) async -> LocalTrackMetadata {
        let asset = AVURLAsset(url: url)
        var title: String?
        var artist: String?
        var album: String?
        var year: Int?

        if let items = try? await asset.load(.commonMetadata) {
            for item in items {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    title = try? await item.load(.stringValue)
                case .commonKeyArtist:
                    artist = try? await item.load(.stringValue)
                case .commonKeyAlbumName:
                    album = try? await item.load(.stringValue)
                case .commonKeyCreationDate:
                    if let dateString = try? await item.load(.stringValue) {
                        year = Int(dateString.prefix(4))
                    }
                default:
                    break
                }
            }
        }

        let durationSeconds = (try? await asset.load(.duration).seconds) ?? 0
        return LocalTrackMetadata(
            title: title, artist: artist, album: album, year: year,
            durationSeconds: durationSeconds.isFinite ? durationSeconds : 0
        )
    }
}
