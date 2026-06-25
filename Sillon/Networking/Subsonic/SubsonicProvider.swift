import Foundation
import CryptoKit

/// Implémentation `ServerProvider` pour un serveur Navidrome ou tout serveur compatible
/// API Subsonic / OpenSubsonic.
///
/// Contrairement à Jellyfin, Subsonic n'a pas de notion de "session" : chaque requête porte
/// ses propres paramètres d'authentification (`u`, `t`, `s`, `v`, `c`, `f`). Cet acteur n'a donc
/// aucun état de session à mettre en cache — chaque appel relit les identifiants depuis le
/// Keychain et (re)calcule un sel/jeton frais en mode mot de passe.
actor SubsonicProvider: ServerProvider {
    private let serverID: UUID
    private let baseURL: URL
    private let username: String
    private let urlSession: URLSession
    private let clientName = "Sillon"
    /// Version d'API Subsonic visée. Choix standard documenté : une version intermédiaire et
    /// largement supportée (Navidrome la prend en charge), plutôt que la toute dernière
    /// extension OpenSubsonic dont le support côté serveurs est plus inégal.
    private let apiVersion = "1.16.1"

    init(serverID: UUID, baseURL: URL, username: String, urlSession: URLSession = .shared) {
        self.serverID = serverID
        self.baseURL = baseURL
        self.username = username
        self.urlSession = urlSession
    }

    // MARK: - Authentification

    func authenticate() async throws -> ProviderSession {
        let body = try await performRequest(path: "ping")
        return ProviderSession(serverDisplayName: nil, serverVersion: body.version, userID: username, token: nil)
    }

    // MARK: - Bibliothèque

    func fetchLibrary() async throws -> LibrarySnapshot {
        let artistsBody = try await performRequest(path: "getArtists")
        let remoteArtists = (artistsBody.artists?.index ?? [])
            .compactMap(\.artist)
            .flatMap { $0 }
            .map { RemoteArtist(id: $0.id, name: $0.name, sortName: nil, coverArtPath: $0.coverArt) }

        let (remoteAlbums, remoteTracks) = try await fetchAllAlbumsAndTracks(type: "alphabeticalByArtist", stopAt: nil)

        let playlistsBody = try await performRequest(path: "getPlaylists")
        var remotePlaylists: [RemotePlaylist] = []
        for summary in playlistsBody.playlists?.playlist ?? [] {
            let detail = try await performRequest(path: "getPlaylist", extraQuery: [URLQueryItem(name: "id", value: summary.id)])
            let trackIDs = (detail.playlist?.entry ?? []).map(\.id)
            remotePlaylists.append(RemotePlaylist(id: summary.id, name: summary.name, trackIDs: trackIDs))
        }

        return LibrarySnapshot(artists: remoteArtists, albums: remoteAlbums, tracks: remoteTracks, playlists: remotePlaylists)
    }

    func syncDelta(since syncCursor: String?) async throws -> SyncDelta {
        guard let cursorString = syncCursor, let cursorDate = ISO8601DateFormatter().date(from: cursorString) else {
            throw ProviderError.unsupportedServerVersion(
                "syncDelta nécessite un curseur existant ; utilisez fetchLibrary() pour la 1ère synchronisation."
            )
        }

        // Approximation documentée : Subsonic/OpenSubsonic n'a pas de mécanisme "changements depuis X"
        // ni de suppressions au niveau morceau/artiste. `getAlbumList2?type=newest` (confirmé) trié par
        // date d'ajout décroissante permet de récupérer les albums ajoutés depuis le curseur — on
        // s'arrête dès qu'on atteint un album plus ancien que le curseur. Couvre le cas d'usage
        // principal ("j'ai ajouté de la musique"), pas les renommages/suppressions, traités par une
        // réconciliation complète périodique via fetchLibrary (cf. moteur de sync, commit suivant).
        let (newAlbums, newTracks) = try await fetchAllAlbumsAndTracks(type: "newest", stopAt: cursorDate)

        return SyncDelta(
            updatedArtists: [],
            updatedAlbums: newAlbums,
            updatedTracks: newTracks,
            updatedPlaylists: [],
            deletedTrackIDs: [],
            deletedAlbumIDs: [],
            deletedArtistIDs: [],
            newSyncCursor: ISO8601DateFormatter().string(from: .now)
        )
    }

    // MARK: - Lecture / téléchargement / pochettes / recherche

    func streamURL(for trackRemoteID: String) async throws -> URL {
        // `format=raw` : confirmé par la spécification (disponible depuis la 1.9.0) — désactive
        // tout transcodage, le serveur renvoie le fichier original.
        try makeAuthenticatedURL(path: "stream", extraQuery: [
            URLQueryItem(name: "id", value: trackRemoteID),
            URLQueryItem(name: "format", value: "raw")
        ])
    }

    func downloadURL(for trackRemoteID: String) async throws -> URL {
        // `download` : endpoint confirmé, distinct de `stream`, garanti sans transcodage.
        try makeAuthenticatedURL(path: "download", extraQuery: [URLQueryItem(name: "id", value: trackRemoteID)])
    }

    func coverArtURL(for remoteID: String, preferredSize: Int?) async throws -> URL? {
        var extra = [URLQueryItem(name: "id", value: remoteID)]
        if let size = preferredSize { extra.append(URLQueryItem(name: "size", value: String(size))) }
        return try? makeAuthenticatedURL(path: "getCoverArt", extraQuery: extra)
    }

    func searchAll(query: String) async throws -> SearchResults {
        let body = try await performRequest(path: "search3", extraQuery: [URLQueryItem(name: "query", value: query)])
        let result = body.searchResult3
        return SearchResults(
            artists: (result?.artist ?? []).map { RemoteArtist(id: $0.id, name: $0.name, sortName: nil, coverArtPath: $0.coverArt) },
            albums: (result?.album ?? []).map(Self.makeRemoteAlbum),
            tracks: (result?.song ?? []).map(Self.makeRemoteTrack)
        )
    }

    // MARK: - Requêtes internes

    /// Parcourt `getAlbumList2` par pages jusqu'à épuisement (ou jusqu'à `stopAt`, pour la synchro
    /// delta), puis récupère le détail (morceaux) de chaque nouvel album via `getAlbum`.
    /// Séquentiel par choix pour cette Phase 1 (priorité à la fiabilité plutôt qu'à la vitesse) ;
    /// une parallélisation bornée pourra être ajoutée plus tard si nécessaire sur de grosses bibliothèques.
    private func fetchAllAlbumsAndTracks(type: String, stopAt cursorDate: Date?) async throws -> ([RemoteAlbum], [RemoteTrack]) {
        var albums: [SubsonicAlbum] = []
        var offset = 0
        let pageSize = 500

        paging: while true {
            let body = try await performRequest(path: "getAlbumList2", extraQuery: [
                URLQueryItem(name: "type", value: type),
                URLQueryItem(name: "size", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset))
            ])
            let page = body.albumList2?.album ?? []
            if page.isEmpty { break }

            for album in page {
                if let cursorDate {
                    guard let createdString = album.created, let created = ISO8601DateFormatter().date(from: createdString) else { continue }
                    if created <= cursorDate { break paging }
                }
                albums.append(album)
            }

            offset += pageSize
            if page.count < pageSize { break }
        }

        var tracks: [RemoteTrack] = []
        // L'objet SubsonicAlbum du listing ne porte pas de ReplayGain ; le détail album (getAlbum)
        // renvoie des song[] qui exposent chacun albumGain/albumPeak. On agrège ces valeurs par album
        // pour les remonter sur le RemoteAlbum (lecture seule — on ne fait que lire ces tags).
        var albumGainByID: [String: (gain: Double?, peak: Double?)] = [:]
        for album in albums {
            let detail = try await performRequest(path: "getAlbum", extraQuery: [URLQueryItem(name: "id", value: album.id)])
            let songs = detail.album?.song ?? []
            tracks.append(contentsOf: songs.map(Self.makeRemoteTrack))
            if let rg = songs.lazy.compactMap({ $0.replayGain }).first(where: { $0.albumGain != nil }) {
                albumGainByID[album.id] = (rg.albumGain, rg.albumPeak)
            }
        }

        let remoteAlbums = albums.map { album -> RemoteAlbum in
            var remote = Self.makeRemoteAlbum(from: album)
            if let agg = albumGainByID[album.id] {
                remote.albumGain = agg.gain
                remote.albumPeak = agg.peak
            }
            return remote
        }
        return (remoteAlbums, tracks)
    }

    func lyrics(forTrackID trackRemoteID: String) async throws -> TrackLyrics? {
        // getLyricsBySongId : extension OpenSubsonic ; renvoie des paroles structurées (synchronisables).
        // Un serveur Subsonic legacy sans l'extension répond status != "ok" → ProviderError, que le
        // LyricsLoader avale pour afficher l'état vide (pas de paroles).
        let body = try await performRequest(
            path: "getLyricsBySongId",
            extraQuery: [URLQueryItem(name: "id", value: trackRemoteID)]
        )
        // Plusieurs variantes possibles (langues/synchro) : on préfère une variante synchronisée avec
        // lignes, sinon la première non vide, sinon la première — pour ne pas afficher « pas de paroles »
        // alors qu'une variante exploitable existe.
        let variants = body.lyricsList?.structuredLyrics ?? []
        guard let structured = variants.first(where: { ($0.synced ?? false) && !($0.line ?? []).isEmpty })
            ?? variants.first(where: { !($0.line ?? []).isEmpty })
            ?? variants.first
        else { return nil }
        let offsetSeconds = Double(structured.offset ?? 0) / 1000.0
        let lines = (structured.line ?? []).map { line in
            LyricLine(timeSeconds: line.start.map { Double($0) / 1000.0 + offsetSeconds }, text: line.value ?? "")
        }
        guard !lines.isEmpty else { return nil }
        let synced = structured.synced ?? lines.contains { $0.timeSeconds != nil }
        return TrackLyrics(synced: synced, lines: lines)
    }

    func radioTracks(seedTrackID: String, limit: Int) async throws -> [RemoteTrack] {
        // On évite getSimilarSongs(2) : l'agent Last.fm peut être indisponible et faire expirer la
        // requête (observé sur ce serveur). Repli rapide et fiable : titres du même GENRE, sinon aléatoires.
        let detail = try await performRequest(path: "getSong", extraQuery: [URLQueryItem(name: "id", value: seedTrackID)])
        let songs: [SubsonicSong]
        if let genre = detail.song?.genre, !genre.isEmpty {
            let body = try await performRequest(path: "getSongsByGenre", extraQuery: [
                URLQueryItem(name: "genre", value: genre),
                URLQueryItem(name: "count", value: String(max(limit * 2, limit + 10)))
            ])
            songs = body.songsByGenre?.song ?? []
        } else {
            let body = try await performRequest(path: "getRandomSongs", extraQuery: [URLQueryItem(name: "size", value: String(limit))])
            songs = body.randomSongs?.song ?? []
        }
        return Array(songs.filter { $0.id != seedTrackID }.shuffled().prefix(limit)).map(Self.makeRemoteTrack)
    }

    private func performRequest(path: String, extraQuery: [URLQueryItem] = []) async throws -> SubsonicResponseBody {
        let url = try makeAuthenticatedURL(path: path, extraQuery: extraQuery)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(from: url)
        } catch {
            throw ProviderError.unreachable(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.unreachable(underlying: URLError(.badServerResponse))
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.unexpectedResponse(statusCode: http.statusCode, body: String(data: data, encoding: .utf8))
        }

        let envelope: SubsonicResponseEnvelope
        do {
            envelope = try JSONDecoder().decode(SubsonicResponseEnvelope.self, from: data)
        } catch {
            throw ProviderError.decodingFailed(underlying: error)
        }

        let result = envelope.subsonicResponse
        guard result.status == "ok" else {
            // Codes d'erreur confirmés par la spécification : 40 = identifiants invalides,
            // 41 = jeton expiré, 42 = authentification par jeton non supportée par le client.
            if let code = result.error?.code, [40, 41, 42].contains(code) {
                throw ProviderError.unauthorized
            }
            throw ProviderError.unexpectedResponse(statusCode: http.statusCode, body: result.error?.message)
        }
        return result
    }

    /// Construit une URL authentifiée pour l'endpoint Subsonic donné (sans le suffixe `.view`,
    /// ajouté ici) et calcule le couple sel/jeton requis par la spécification.
    ///
    /// Deux modes sont supportés, conformément au formulaire d'ajout de serveur ("password/token+salt") :
    /// - **Mot de passe** : un sel aléatoire est généré à chaque requête et le jeton recalculé
    ///   (`t = MD5(password + salt)`), recommandé par la spécification pour éviter de rejouer un jeton capturé.
    /// - **Jeton + sel fixes** : l'utilisateur a lui-même calculé un couple jeton/sel (avec un sel de son
    ///   choix) et ne souhaite pas que l'app connaisse son mot de passe en clair. On réutilise alors ce
    ///   couple tel quel sur chaque requête.
    private func makeAuthenticatedURL(path: String, extraQuery: [URLQueryItem] = []) throws -> URL {
        let salt: String
        let token: String

        if let fixedToken = KeychainStore.read(for: serverID, field: .apiToken),
           let fixedSalt = KeychainStore.read(for: serverID, field: .subsonicSalt) {
            salt = fixedSalt
            token = fixedToken
        } else if let password = KeychainStore.read(for: serverID, field: .password) {
            // `Insecure.MD5` (CryptoKit) : l'espace de noms "Insecure" signale la faiblesse de MD5 en
            // tant qu'algorithme cryptographique général — pas un choix de notre part, c'est l'algorithme
            // imposé par le protocole Subsonic lui-même (t = MD5(password + salt)).
            salt = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            token = Insecure.MD5.hash(data: Data((password + salt).utf8))
                .map { String(format: "%02hhx", $0) }
                .joined()
        } else {
            throw ProviderError.missingCredentials
        }

        guard var components = URLComponents(url: baseURL.appending(path: "rest/\(path).view"), resolvingAgainstBaseURL: false) else {
            throw ProviderError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "c", value: clientName),
            URLQueryItem(name: "f", value: "json")
        ] + extraQuery

        guard let url = components.url else { throw ProviderError.invalidURL }
        return url
    }

    // MARK: - Conversion DTO -> modèles de synchronisation

    private static func makeRemoteAlbum(from album: SubsonicAlbum) -> RemoteAlbum {
        RemoteAlbum(
            id: album.id,
            artistID: album.artistId,
            artistName: album.artist,
            title: album.name,
            year: album.year,
            coverArtPath: album.coverArt,
            dateAdded: album.created.flatMap { ISO8601DateFormatter().date(from: $0) }
        )
    }

    private static func makeRemoteTrack(from song: SubsonicSong) -> RemoteTrack {
        let rg = song.replayGain
        return RemoteTrack(
            id: song.id,
            albumID: song.albumId,
            albumTitle: song.album,
            artistName: song.artist,
            title: song.title,
            trackNumber: song.track,
            discNumber: song.discNumber,
            durationSeconds: Double(song.duration ?? 0),
            format: song.suffix,
            bitrate: song.bitRate,
            dateAdded: song.created.flatMap { ISO8601DateFormatter().date(from: $0) },
            genre: song.genre,
            // baseGain (ex. Opus output gain) s'applique quel que soit le mode => on le somme aux deux.
            trackGain: sum(rg?.trackGain, rg?.baseGain),
            trackPeak: rg?.trackPeak,
            albumGain: sum(rg?.albumGain, rg?.baseGain),
            albumPeak: rg?.albumPeak,
            fallbackGain: rg?.fallbackGain
        )
    }

    /// Somme deux gains en dB en propageant `nil` : si le gain principal est absent on renvoie nil
    /// (pour pouvoir basculer sur le fallback côté lecteur), sinon on ajoute le baseGain s'il existe.
    private static func sum(_ gain: Double?, _ base: Double?) -> Double? {
        guard let gain else { return nil }
        return gain + (base ?? 0)
    }
}
