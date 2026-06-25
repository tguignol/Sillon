import Foundation

/// Implémentation `ServerProvider` pour un serveur Jellyfin.
///
/// `actor` : voir la justification dans `ServerProvider.swift` (sécurité de concurrence).
/// Le jeton (`AccessToken`) et l'identifiant utilisateur sont mis en cache en mémoire après
/// authentification — contrairement à Subsonic, Jellyfin exige un appel explicite à
/// `/Users/AuthenticateByName` pour obtenir un jeton ; il n'y a pas de calcul "par requête"
/// comme le couple sel/jeton de Subsonic, donc la mise en cache est nécessaire ici.
actor JellyfinProvider: ServerProvider {
    private let serverID: UUID
    private let baseURL: URL
    private let username: String
    private let urlSession: URLSession

    private let clientName = "Sillon"
    private let clientVersion = "1.0"
    private let deviceID: String

    private var cachedToken: String?
    private var cachedUserID: String?

    init(serverID: UUID, baseURL: URL, username: String, urlSession: URLSession? = nil) {
        self.serverID = serverID
        self.baseURL = baseURL
        self.username = username
        self.urlSession = urlSession ?? Self.makeDefaultSession()
        self.deviceID = Self.persistentDeviceID()
    }

    /// Session par défaut tolérante aux serveurs auto-hébergés lents/distants : on relève le délai
    /// d'expiration par requête (le défaut de 60 s ne suffit pas pour une page de bibliothèque sur
    /// un serveur domestique via internet) et on attend la connectivité plutôt que d'échouer aussitôt.
    private static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }

    // MARK: - Authentification

    func authenticate() async throws -> ProviderSession {
        guard let password = KeychainStore.read(for: serverID, field: .password) else {
            throw ProviderError.missingCredentials
        }

        var request = URLRequest(url: baseURL.appending(path: "Users/AuthenticateByName"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // En-tête `X-Emby-Authorization` plutôt que `Authorization` : ce dernier est un nom d'en-tête
        // réservé par les frameworks réseau d'Apple et peut être intercepté/réécrit par le système
        // dans certains contextes — un point régulièrement signalé par des développeurs iOS dans
        // l'écosystème Jellyfin. `X-Emby-Authorization` est le nom historique, accepté par tous les
        // serveurs Jellyfin, qui évite ce risque.
        request.setValue(authorizationHeaderValue(includingToken: false), forHTTPHeaderField: "X-Emby-Authorization")
        request.httpBody = try JSONEncoder().encode(["Username": username, "Pw": password])

        let (data, response) = try await perform(request)
        try Self.validate(response, data: data)

        let result: JellyfinAuthenticationResult
        do {
            result = try JSONDecoder().decode(JellyfinAuthenticationResult.self, from: data)
        } catch {
            throw ProviderError.decodingFailed(underlying: error)
        }

        cachedToken = result.AccessToken
        cachedUserID = result.User.Id

        // Best-effort : la version serveur n'est qu'informative, son indisponibilité ne doit pas
        // faire échouer une authentification par ailleurs réussie.
        let serverVersion = try? await fetchPublicServerVersion()

        return ProviderSession(
            serverDisplayName: nil,
            serverVersion: serverVersion,
            userID: result.User.Id,
            token: result.AccessToken
        )
    }

    private func ensureAuthenticated() async throws {
        if cachedToken == nil || cachedUserID == nil {
            _ = try await authenticate()
        }
    }

    // MARK: - Bibliothèque

    func fetchLibrary() async throws -> LibrarySnapshot {
        try await ensureAuthenticated()

        let artistItems = try await fetchItems(includeItemTypes: "MusicArtist")
        let albumItems = try await fetchItems(includeItemTypes: "MusicAlbum")
        let trackItems = try await fetchItems(includeItemTypes: "Audio")
        let playlistItems = try await fetchItems(includeItemTypes: "Playlist")

        var remotePlaylists: [RemotePlaylist] = []
        for playlist in playlistItems {
            let trackIDs = try await fetchPlaylistItemIDs(playlistID: playlist.Id)
            remotePlaylists.append(RemotePlaylist(id: playlist.Id, name: playlist.Name ?? "Playlist", trackIDs: trackIDs))
        }

        return LibrarySnapshot(
            artists: artistItems.map(Self.makeRemoteArtist),
            albums: albumItems.map(Self.makeRemoteAlbum),
            tracks: trackItems.map(Self.makeRemoteTrack),
            playlists: remotePlaylists
        )
    }

    func syncDelta(since syncCursor: String?) async throws -> SyncDelta {
        guard let cursor = syncCursor else {
            throw ProviderError.unsupportedServerVersion(
                "syncDelta nécessite un curseur existant ; utilisez fetchLibrary() pour la 1ère synchronisation."
            )
        }
        try await ensureAuthenticated()

        let artistItems = try await fetchItems(includeItemTypes: "MusicArtist", extraQuery: ["MinDateLastSaved": cursor])
        let albumItems = try await fetchItems(includeItemTypes: "MusicAlbum", extraQuery: ["MinDateLastSaved": cursor])
        let trackItems = try await fetchItems(includeItemTypes: "Audio", extraQuery: ["MinDateLastSaved": cursor])
        let playlistItems = try await fetchItems(includeItemTypes: "Playlist", extraQuery: ["MinDateLastSaved": cursor])

        var remotePlaylists: [RemotePlaylist] = []
        for playlist in playlistItems {
            let trackIDs = try await fetchPlaylistItemIDs(playlistID: playlist.Id)
            remotePlaylists.append(RemotePlaylist(id: playlist.Id, name: playlist.Name ?? "Playlist", trackIDs: trackIDs))
        }

        // LIMITE DOCUMENTÉE : `MinDateLastSaved` (confirmé sur l'endpoint /Items) renvoie les éléments
        // ajoutés/modifiés depuis le curseur, mais Jellyfin n'expose pas d'endpoint public confirmé
        // pour les suppressions à ce niveau. On ne les détecte donc pas ici ; elles seront rattrapées
        // par une réconciliation complète périodique (fetchLibrary), orchestrée par le moteur de sync
        // (commit "Synchronisation"). On préfère cette limite explicite à un mécanisme inventé.
        return SyncDelta(
            updatedArtists: artistItems.map(Self.makeRemoteArtist),
            updatedAlbums: albumItems.map(Self.makeRemoteAlbum),
            updatedTracks: trackItems.map(Self.makeRemoteTrack),
            updatedPlaylists: remotePlaylists,
            deletedTrackIDs: [],
            deletedAlbumIDs: [],
            deletedArtistIDs: [],
            newSyncCursor: ISO8601DateFormatter().string(from: .now)
        )
    }

    // MARK: - Lecture / téléchargement / pochettes / recherche

    func streamURL(for trackRemoteID: String) async throws -> URL {
        try await ensureAuthenticated()
        guard let token = cachedToken else { throw ProviderError.missingCredentials }

        guard var components = URLComponents(url: baseURL.appending(path: "Audio/\(trackRemoteID)/stream"), resolvingAgainstBaseURL: false) else {
            throw ProviderError.invalidURL
        }
        // `static=true` : confirmé — lecture du fichier original sans transcodage.
        components.queryItems = [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "api_key", value: token)
        ]
        guard let url = components.url else { throw ProviderError.invalidURL }
        return url
    }

    func downloadURL(for trackRemoteID: String) async throws -> URL {
        // Jellyfin n'expose pas d'endpoint "download" distinct pour l'audio : `stream?static=true`
        // EST déjà le fichier original, sans transcodage. On réutilise donc la même URL.
        try await streamURL(for: trackRemoteID)
    }

    func coverArtURL(for remoteID: String, preferredSize: Int?) async throws -> URL? {
        if cachedToken == nil { _ = try? await authenticate() }

        guard var components = URLComponents(url: baseURL.appending(path: "Items/\(remoteID)/Images/Primary"), resolvingAgainstBaseURL: false) else {
            return nil
        }
        var query: [URLQueryItem] = []
        if let size = preferredSize { query.append(URLQueryItem(name: "maxWidth", value: String(size))) }
        if let token = cachedToken { query.append(URLQueryItem(name: "api_key", value: token)) }
        components.queryItems = query.isEmpty ? nil : query
        return components.url
    }

    func searchAll(query: String) async throws -> SearchResults {
        try await ensureAuthenticated()
        let artistItems = try await fetchItems(includeItemTypes: "MusicArtist", extraQuery: ["SearchTerm": query])
        let albumItems = try await fetchItems(includeItemTypes: "MusicAlbum", extraQuery: ["SearchTerm": query])
        let trackItems = try await fetchItems(includeItemTypes: "Audio", extraQuery: ["SearchTerm": query])
        return SearchResults(
            artists: artistItems.map(Self.makeRemoteArtist),
            albums: albumItems.map(Self.makeRemoteAlbum),
            tracks: trackItems.map(Self.makeRemoteTrack)
        )
    }

    func lyrics(forTrackID trackRemoteID: String) async throws -> TrackLyrics? {
        try await ensureAuthenticated()
        let url = baseURL.appending(path: "Audio/\(trackRemoteID)/Lyrics")
        var request = URLRequest(url: url)
        request.setValue(authorizationHeaderValue(includingToken: true), forHTTPHeaderField: "X-Emby-Authorization")

        let (data, response) = try await perform(request)
        // 404 = pas de paroles pour ce morceau : cas normal, on renvoie nil sans lever d'erreur.
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { return nil }
        try Self.validate(response, data: data)

        let decoded: JellyfinLyricsResponse
        do { decoded = try JSONDecoder().decode(JellyfinLyricsResponse.self, from: data) }
        catch { throw ProviderError.decodingFailed(underlying: error) }

        let lines = (decoded.Lyrics ?? []).map { line in
            // Start en ticks .NET (1 tick = 100 ns), comme RunTimeTicks → secondes = ticks / 10_000_000.
            LyricLine(timeSeconds: line.Start.map { Double($0) / 10_000_000.0 }, text: line.Text ?? "")
        }
        guard !lines.isEmpty else { return nil }
        return TrackLyrics(synced: lines.contains { $0.timeSeconds != nil }, lines: lines)
    }

    func radioTracks(seedTrackID: String, limit: Int) async throws -> [RemoteTrack] {
        try await ensureAuthenticated()
        guard let userID = cachedUserID else { throw ProviderError.missingCredentials }
        // InstantMix : mix instantané local (genres/métadonnées), sans dépendance externe.
        guard var components = URLComponents(url: baseURL.appending(path: "Items/\(seedTrackID)/InstantMix"), resolvingAgainstBaseURL: false) else {
            throw ProviderError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "UserId", value: userID),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: "DateCreated,MediaStreams,SortName")
        ]
        guard let url = components.url else { throw ProviderError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(authorizationHeaderValue(includingToken: true), forHTTPHeaderField: "X-Emby-Authorization")
        let (data, response) = try await perform(request)
        try Self.validate(response, data: data)
        let decoded = try JSONDecoder().decode(JellyfinItemsResponse.self, from: data)
        return decoded.Items.map(Self.makeRemoteTrack)
    }

    // MARK: - Requêtes internes

    private func fetchItems(includeItemTypes: String, extraQuery: [String: String] = [:]) async throws -> [JellyfinBaseItem] {
        guard let userID = cachedUserID else { throw ProviderError.missingCredentials }

        // Pagination : on récupère la bibliothèque par pages de `pageSize` (`StartIndex`/`Limit`)
        // plutôt qu'en une seule requête de 5000 éléments — cette dernière, avec `MediaStreams`,
        // dépasse le délai d'expiration sur un vrai serveur domestique (timeout -1001 observé en test
        // réel). On s'arrête dès qu'une page est incomplète ou que le total annoncé est atteint.
        let pageSize = 500
        var startIndex = 0
        var collected: [JellyfinBaseItem] = []

        while true {
            guard var components = URLComponents(url: baseURL.appending(path: "Users/\(userID)/Items"), resolvingAgainstBaseURL: false) else {
                throw ProviderError.invalidURL
            }
            var query: [URLQueryItem] = [
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "IncludeItemTypes", value: includeItemTypes),
                URLQueryItem(name: "Fields", value: "DateCreated,MediaStreams,SortName,NormalizationGain,Genres"),
                URLQueryItem(name: "SortBy", value: "SortName"),
                URLQueryItem(name: "StartIndex", value: String(startIndex)),
                URLQueryItem(name: "Limit", value: String(pageSize))
            ]
            for (key, value) in extraQuery { query.append(URLQueryItem(name: key, value: value)) }
            components.queryItems = query

            guard let url = components.url else { throw ProviderError.invalidURL }
            var request = URLRequest(url: url)
            request.setValue(authorizationHeaderValue(includingToken: true), forHTTPHeaderField: "X-Emby-Authorization")

            let (data, response) = try await perform(request)
            try Self.validate(response, data: data)

            let page: JellyfinItemsResponse
            do {
                page = try JSONDecoder().decode(JellyfinItemsResponse.self, from: data)
            } catch {
                throw ProviderError.decodingFailed(underlying: error)
            }

            collected.append(contentsOf: page.Items)

            if page.Items.count < pageSize { break }
            if let total = page.TotalRecordCount, collected.count >= total { break }
            startIndex += pageSize
            if startIndex > 1_000_000 { break }   // garde-fou anti-boucle
        }

        return collected
    }

    private func fetchPlaylistItemIDs(playlistID: String) async throws -> [String] {
        guard let userID = cachedUserID else { throw ProviderError.missingCredentials }
        guard var components = URLComponents(url: baseURL.appending(path: "Playlists/\(playlistID)/Items"), resolvingAgainstBaseURL: false) else {
            throw ProviderError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "UserId", value: userID)]
        guard let url = components.url else { throw ProviderError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue(authorizationHeaderValue(includingToken: true), forHTTPHeaderField: "X-Emby-Authorization")

        let (data, response) = try await perform(request)
        try Self.validate(response, data: data)
        let decoded = try JSONDecoder().decode(JellyfinItemsResponse.self, from: data)
        return decoded.Items.map(\.Id)
    }

    private func fetchPublicServerVersion() async throws -> String? {
        let request = URLRequest(url: baseURL.appending(path: "System/Info/Public"))
        let (data, response) = try await perform(request)
        try Self.validate(response, data: data)
        return try JSONDecoder().decode(JellyfinPublicSystemInfo.self, from: data).Version
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch {
            throw ProviderError.unreachable(underlying: error)
        }
    }

    private func authorizationHeaderValue(includingToken: Bool) -> String {
        var value = "MediaBrowser Client=\"\(clientName)\", Device=\"Sillon\", DeviceId=\"\(deviceID)\", Version=\"\(clientVersion)\""
        if includingToken, let token = cachedToken {
            value += ", Token=\"\(token)\""
        }
        return value
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.unreachable(underlying: URLError(.badServerResponse))
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw ProviderError.unauthorized }
            throw ProviderError.unexpectedResponse(statusCode: http.statusCode, body: String(data: data, encoding: .utf8))
        }
    }

    /// Identifiant d'appareil stable, requis par l'en-tête d'authentification Jellyfin.
    /// Un seul par installation de l'app, persisté en `UserDefaults` (pas un secret).
    private static func persistentDeviceID() -> String {
        let key = "app.sillon.jellyfin.deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }

    // MARK: - Conversion DTO -> modèles de synchronisation

    private static func makeRemoteArtist(from item: JellyfinBaseItem) -> RemoteArtist {
        RemoteArtist(
            id: item.Id,
            name: item.Name ?? "Artiste inconnu",
            sortName: item.SortName,
            coverArtPath: item.ImageTags?.Primary != nil ? item.Id : nil
        )
    }

    private static func makeRemoteAlbum(from item: JellyfinBaseItem) -> RemoteAlbum {
        RemoteAlbum(
            id: item.Id,
            artistID: item.ArtistItems?.first?.Id,
            artistName: item.AlbumArtist ?? item.ArtistItems?.first?.Name,
            title: item.Name ?? "Album inconnu",
            year: item.ProductionYear,
            coverArtPath: item.ImageTags?.Primary != nil ? item.Id : nil,
            dateAdded: parseDate(item.DateCreated)
        )
    }

    private static func makeRemoteTrack(from item: JellyfinBaseItem) -> RemoteTrack {
        RemoteTrack(
            id: item.Id,
            albumID: item.AlbumId,
            albumTitle: item.Album,
            artistName: item.ArtistItems?.first?.Name ?? item.AlbumArtist,
            title: item.Name ?? "Titre inconnu",
            trackNumber: item.IndexNumber,
            discNumber: item.ParentIndexNumber,
            durationSeconds: item.durationSeconds,
            format: item.audioCodec,
            bitrate: item.audioBitRate,
            dateAdded: parseDate(item.DateCreated),
            genre: item.Genres?.first,
            // Jellyfin n'expose qu'un gain piste (NormalizationGain), sans peak ni gain album.
            trackGain: item.NormalizationGain
        )
    }

    /// Analyse défensive : Jellyfin renvoie parfois des fractions de seconde à une précision
    /// (ticks .NET) que `ISO8601DateFormatter` n'accepte pas. En cas d'échec des deux formats
    /// essayés, on renvoie `nil` plutôt qu'une date inventée — l'horodatage "ajouté le" sera
    /// simplement absent pour cet élément.
    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return isoFormatterFractional.date(from: string) ?? isoFormatter.date(from: string)
    }

    private static let isoFormatter = ISO8601DateFormatter()
    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
