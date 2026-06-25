import Foundation
import SwiftData

/// Moteur de synchronisation : convertit les DTOs `Sendable` renvoyés par un `ServerProvider`
/// (`LibrarySnapshot` / `SyncDelta`) en modèles SwiftData persistés, et tient à jour les
/// horodatages + le curseur de synchro.
///
/// Stratégie (cf. contrainte "scan delta, pas full re-scan sauf 1ère fois", `ServerProvider`) :
/// - 1ʳᵉ synchro (`!hasCompletedInitialSync`) → `fetchLibrary()` (scan complet) ;
/// - synchros suivantes → `syncDelta(since:)` à partir du `syncCursor` mémorisé.
///
/// Tout le travail SwiftData se fait sur le `MainActor` (le `ModelContext` de l'UI y est lié) ;
/// les appels réseau, eux, sont `await`és sur les acteurs `ServerProvider` sans bloquer l'UI.
@MainActor
enum LibrarySyncService {

    /// État de progression remonté à l'UI pendant une synchro.
    struct Progress: Equatable {
        enum Phase: Equatable {
            case authenticating
            case fetchingLibrary   // scan complet
            case fetchingDelta     // synchro incrémentale
            case applying          // écriture SwiftData
            case done
        }
        var phase: Phase
        var processed: Int = 0
        var total: Int = 0

        var fraction: Double {
            guard total > 0 else { return phase == .done ? 1 : 0 }
            return min(1, Double(processed) / Double(total))
        }
    }

    /// Synchronise un serveur. Met à jour les modèles SwiftData *in place* dans `context`
    /// (l'appelant est responsable de l'éventuelle sauvegarde — l'autosave SwiftData par défaut suffit).
    /// Relance les erreurs des providers telles quelles (l'appelant les présente à l'utilisateur).
    static func synchronize(
        _ server: ServerAccount,
        context: ModelContext,
        onProgress: (Progress) -> Void = { _ in }
    ) async throws {
        let provider = try ServerProviderFactory.makeProvider(for: server)
        try await synchronize(server, using: provider, context: context, onProgress: onProgress)
    }

    /// Variante avec provider injecté — couture de test : permet d'exercer l'upsert SwiftData avec
    /// un provider factice (sans réseau), tout en partageant exactement la logique de production.
    static func synchronize(
        _ server: ServerAccount,
        using provider: any ServerProvider,
        context: ModelContext,
        onProgress: (Progress) -> Void = { _ in }
    ) async throws {
        onProgress(Progress(phase: .authenticating))
        _ = try await provider.authenticate()

        if server.hasCompletedInitialSync {
            onProgress(Progress(phase: .fetchingDelta))
            let delta = try await provider.syncDelta(since: server.syncCursor)
            apply(delta: delta, to: server, context: context, onProgress: onProgress)
            if let cursor = delta.newSyncCursor { server.syncCursor = cursor }
        } else {
            onProgress(Progress(phase: .fetchingLibrary))
            let snapshot = try await provider.fetchLibrary()
            applyFull(snapshot: snapshot, to: server, context: context, onProgress: onProgress)
            server.lastFullSyncDate = .now
            // `fetchLibrary()` ne renvoie pas de curseur ; on amorce le prochain delta avec l'instant
            // présent (format ISO8601, commun aux trois providers — cf. leurs `syncDelta`).
            server.syncCursor = ISO8601DateFormatter().string(from: .now)
        }

        server.lastDeltaSyncDate = .now

        // Persistance déterministe : on sauvegarde explicitement en fin de synchro plutôt que de
        // dépendre de l'autosave, pour que la bibliothèque soit durablement écrite immédiatement
        // (et pour rendre l'opération vérifiable en test).
        if context.hasChanges { try context.save() }

        onProgress(Progress(phase: .done))
    }

    // MARK: - Application des changements

    private static func applyFull(
        snapshot: LibrarySnapshot,
        to server: ServerAccount,
        context: ModelContext,
        onProgress: (Progress) -> Void
    ) {
        let index = LibraryIndex(server: server, context: context)
        let total = snapshot.artists.count + snapshot.albums.count + snapshot.tracks.count
        var progress = Progress(phase: .applying, total: total)

        upsertArtists(snapshot.artists, server: server, context: context, index: index, progress: &progress, onProgress: onProgress)
        upsertAlbums(snapshot.albums, server: server, context: context, index: index, progress: &progress, onProgress: onProgress)
        upsertTracks(snapshot.tracks, server: server, context: context, index: index, progress: &progress, onProgress: onProgress)
        // Playlists distantes : non importées en Phase 1 (cf. Docs/DECISIONS.md #14).
    }

    private static func apply(
        delta: SyncDelta,
        to server: ServerAccount,
        context: ModelContext,
        onProgress: (Progress) -> Void
    ) {
        let index = LibraryIndex(server: server, context: context)
        let total = delta.updatedArtists.count + delta.updatedAlbums.count + delta.updatedTracks.count
        var progress = Progress(phase: .applying, total: total)

        upsertArtists(delta.updatedArtists, server: server, context: context, index: index, progress: &progress, onProgress: onProgress)
        upsertAlbums(delta.updatedAlbums, server: server, context: context, index: index, progress: &progress, onProgress: onProgress)
        upsertTracks(delta.updatedTracks, server: server, context: context, index: index, progress: &progress, onProgress: onProgress)

        // Suppressions : les providers actuels n'en signalent pas (cf. Docs/DECISIONS.md #10),
        // mais le moteur les applique dès qu'elles seront fournies — supprimer les morceaux d'abord
        // évite de laisser des albums/artistes orphelins référencés.
        for remoteID in delta.deletedTrackIDs { index.track(remoteID).map(context.delete) }
        for remoteID in delta.deletedAlbumIDs { index.album(remoteID).map(context.delete) }
        for remoteID in delta.deletedArtistIDs { index.artist(remoteID).map(context.delete) }
    }

    // MARK: - Upserts

    private static func upsertArtists(
        _ remotes: [RemoteArtist],
        server: ServerAccount,
        context: ModelContext,
        index: LibraryIndex,
        progress: inout Progress,
        onProgress: (Progress) -> Void
    ) {
        for remote in remotes {
            let artist = index.artist(remote.id) ?? {
                let new = Artist(serverID: server.id, remoteID: remote.id, name: remote.name, sortName: remote.sortName)
                new.server = server
                context.insert(new)
                index.register(new)
                return new
            }()
            artist.name = remote.name
            artist.sortName = remote.sortName ?? remote.name
            artist.coverArtRemotePath = remote.coverArtPath
            tick(&progress, onProgress)
        }
    }

    private static func upsertAlbums(
        _ remotes: [RemoteAlbum],
        server: ServerAccount,
        context: ModelContext,
        index: LibraryIndex,
        progress: inout Progress,
        onProgress: (Progress) -> Void
    ) {
        for remote in remotes {
            let album = index.album(remote.id) ?? {
                let new = Album(serverID: server.id, remoteID: remote.id, title: remote.title)
                new.server = server
                context.insert(new)
                index.register(new)
                return new
            }()
            album.title = remote.title
            album.year = remote.year
            album.coverArtRemotePath = remote.coverArtPath
            album.dateAdded = remote.dateAdded
            album.artistNameSnapshot = remote.artistName
            album.albumGain = remote.albumGain
            album.albumPeak = remote.albumPeak
            if let artistID = remote.artistID { album.artist = index.artist(artistID) }
            tick(&progress, onProgress)
        }
    }

    private static func upsertTracks(
        _ remotes: [RemoteTrack],
        server: ServerAccount,
        context: ModelContext,
        index: LibraryIndex,
        progress: inout Progress,
        onProgress: (Progress) -> Void
    ) {
        for remote in remotes {
            let track = index.track(remote.id) ?? {
                let new = Track(serverID: server.id, remoteID: remote.id, title: remote.title, durationSeconds: remote.durationSeconds)
                new.server = server
                context.insert(new)
                index.register(new)
                return new
            }()
            track.title = remote.title
            track.trackNumber = remote.trackNumber
            track.discNumber = remote.discNumber
            track.durationSeconds = remote.durationSeconds
            track.format = remote.format
            track.bitrate = remote.bitrate
            track.dateAdded = remote.dateAdded
            track.artistNameSnapshot = remote.artistName
            // ReplayGain (lecture seule) ; Subsonic fournit aussi albumGain/peak par song, ce qui
            // permet au lecteur de résoudre le mode « album » sans charger la relation `album`.
            track.trackGain = remote.trackGain
            track.trackPeak = remote.trackPeak
            track.albumGain = remote.albumGain
            track.albumPeak = remote.albumPeak
            track.fallbackGain = remote.fallbackGain
            if let albumID = remote.albumID { track.album = index.album(albumID) }
            tick(&progress, onProgress)
        }
    }

    /// Avance le compteur et notifie l'UI, en limitant la fréquence pour ne pas la saturer.
    private static func tick(_ progress: inout Progress, _ onProgress: (Progress) -> Void) {
        progress.processed += 1
        if progress.processed % 25 == 0 || progress.processed == progress.total {
            onProgress(progress)
        }
    }
}

/// Index en mémoire des modèles existants d'un serveur, indexés par `remoteID`.
///
/// Évite une requête SwiftData par élément pendant l'upsert : on charge une fois les modèles du
/// serveur (filtrés par le préfixe `<serverID>:` de leur identifiant composite), puis on enrichit
/// l'index au fur et à mesure des insertions.
@MainActor
private final class LibraryIndex {
    private var artists: [String: Artist]
    private var albums: [String: Album]
    private var tracks: [String: Track]

    init(server: ServerAccount, context: ModelContext) {
        // On filtre par le préfixe `<serverID>:` *en mémoire* plutôt que via un `#Predicate`
        // `starts(with:)` : ce dernier compile mais n'est pas traduisible par le moteur SwiftData
        // et provoque un trap à l'exécution. Le filtrage Swift est garanti correct ; le surcoût
        // (charger tous les modèles, toutes sources confondues) reste acceptable aux volumes de
        // Phase 1 — une requête indexée pourra être introduite plus tard si nécessaire.
        let prefix = "\(server.id.uuidString):"
        func belongs<T>(_ items: [T], _ id: (T) -> String) -> [T] { items.filter { id($0).hasPrefix(prefix) } }

        let allArtists = (try? context.fetch(FetchDescriptor<Artist>())) ?? []
        let allAlbums = (try? context.fetch(FetchDescriptor<Album>())) ?? []
        let allTracks = (try? context.fetch(FetchDescriptor<Track>())) ?? []

        artists = Dictionary(belongs(allArtists, \.id).map { ($0.remoteID, $0) }, uniquingKeysWith: { a, _ in a })
        albums = Dictionary(belongs(allAlbums, \.id).map { ($0.remoteID, $0) }, uniquingKeysWith: { a, _ in a })
        tracks = Dictionary(belongs(allTracks, \.id).map { ($0.remoteID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func artist(_ remoteID: String) -> Artist? { artists[remoteID] }
    func album(_ remoteID: String) -> Album? { albums[remoteID] }
    func track(_ remoteID: String) -> Track? { tracks[remoteID] }

    func register(_ artist: Artist) { artists[artist.remoteID] = artist }
    func register(_ album: Album) { albums[album.remoteID] = album }
    func register(_ track: Track) { tracks[track.remoteID] = track }
}
