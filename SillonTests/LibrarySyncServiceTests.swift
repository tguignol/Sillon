import Testing
import Foundation
import SwiftData
@testable import Sillon

/// Provider factice : renvoie une bibliothèque/un delta fixes, sans réseau. Permet d'exercer le
/// moteur de synchronisation (upsert SwiftData, relations, horodatages) de façon déterministe.
actor StubProvider: ServerProvider {
    var snapshot: LibrarySnapshot
    var delta: SyncDelta
    var favorites: RemoteFavorites

    init(snapshot: LibrarySnapshot, delta: SyncDelta, favorites: RemoteFavorites = .empty) {
        self.snapshot = snapshot
        self.delta = delta
        self.favorites = favorites
    }

    func authenticate() async throws -> ProviderSession { ProviderSession() }
    func fetchLibrary() async throws -> LibrarySnapshot { snapshot }
    func syncDelta(since syncCursor: String?) async throws -> SyncDelta { delta }
    func streamURL(for trackRemoteID: String) async throws -> URL { URL(string: "https://example.invalid")! }
    func downloadURL(for trackRemoteID: String) async throws -> URL { URL(string: "https://example.invalid")! }
    func coverArtURL(for remoteID: String, preferredSize: Int?) async throws -> URL? { nil }
    func searchAll(query: String) async throws -> SearchResults { SearchResults(artists: [], albums: [], tracks: []) }
    func lyrics(forTrackID trackRemoteID: String) async throws -> TrackLyrics? { nil }
    func radioTracks(seedTrackID: String, limit: Int) async throws -> [RemoteTrack] { [] }
    func serverFavorites() async throws -> RemoteFavorites { favorites }
}

@MainActor
struct LibrarySyncServiceTests {

    /// Contexte de test sur store in-memory, **autosave désactivé**. L'autosave asynchrone du
    /// `mainContext`, sur un container in-memory jetable, se déclenche après la fin du test (contexte
    /// en cours de désallocation) et fait planter le process de test — artefact propre aux tests, sans
    /// impact sur l'app réelle dont le container vit pendant toute la session. Le moteur de sync
    /// sauvegarde de toute façon explicitement, donc les assertions voient bien les données.
    private func makeContext() -> ModelContext {
        let context = ModelContext(SillonSchema.makeContainer(inMemory: true))
        context.autosaveEnabled = false
        return context
    }

    private func snapshot() -> LibrarySnapshot {
        LibrarySnapshot(
            artists: [RemoteArtist(id: "a1", name: "Miles Davis", sortName: nil, coverArtPath: nil)],
            albums: [RemoteAlbum(id: "al1", artistID: "a1", artistName: "Miles Davis", title: "Kind of Blue", year: 1959, coverArtPath: nil, dateAdded: .now)],
            tracks: [
                RemoteTrack(id: "t1", albumID: "al1", albumTitle: "Kind of Blue", artistName: "Miles Davis", title: "So What", trackNumber: 1, discNumber: 1, durationSeconds: 545, format: "flac", bitrate: 1024, dateAdded: .now),
                RemoteTrack(id: "t2", albumID: "al1", albumTitle: "Kind of Blue", artistName: "Miles Davis", title: "Blue in Green", trackNumber: 2, discNumber: 1, durationSeconds: 327, format: "flac", bitrate: 1024, dateAdded: .now)
            ],
            playlists: []
        )
    }

    private func emptyDelta() -> SyncDelta {
        SyncDelta(updatedArtists: [], updatedAlbums: [], updatedTracks: [], updatedPlaylists: [],
                  deletedTrackIDs: [], deletedAlbumIDs: [], deletedArtistIDs: [], newSyncCursor: nil)
    }

    @Test func fullSyncPersistsLibraryAndLinksRelationships() async throws {
        let context = makeContext()
        let server = ServerAccount(name: "Démo", type: .jellyfin)
        context.insert(server)
        let provider = StubProvider(snapshot: snapshot(), delta: emptyDelta())

        try await LibrarySyncService.synchronize(server, using: provider, context: context)

        let artists = try context.fetch(FetchDescriptor<Artist>())
        let albums = try context.fetch(FetchDescriptor<Album>())
        let tracks = try context.fetch(FetchDescriptor<Track>())

        #expect(artists.count == 1)
        #expect(albums.count == 1)
        #expect(tracks.count == 2)

        // Relations correctement câblées par le moteur.
        #expect(albums.first?.artist?.name == "Miles Davis")
        #expect(tracks.allSatisfy { $0.album?.title == "Kind of Blue" })
        #expect(albums.first?.tracks.count == 2)

        // Horodatages + curseur amorcés.
        #expect(server.lastFullSyncDate != nil)
        #expect(server.lastDeltaSyncDate != nil)
        #expect(server.syncCursor != nil)
        #expect(server.hasCompletedInitialSync)
    }

    @Test func secondSyncRunsDeltaAndUpsertsInPlace() async throws {
        let context = makeContext()
        let server = ServerAccount(name: "Démo", type: .jellyfin)
        context.insert(server)

        // 1ʳᵉ synchro : scan complet.
        let firstProvider = StubProvider(snapshot: snapshot(), delta: emptyDelta())
        try await LibrarySyncService.synchronize(server, using: firstProvider, context: context)

        // 2ᵉ synchro : delta qui met à jour un titre existant et ajoute un nouvel album.
        let delta = SyncDelta(
            updatedArtists: [],
            updatedAlbums: [RemoteAlbum(id: "al2", artistID: "a1", artistName: "Miles Davis", title: "Milestones", year: 1958, coverArtPath: nil, dateAdded: .now)],
            updatedTracks: [RemoteTrack(id: "t1", albumID: "al1", albumTitle: "Kind of Blue", artistName: "Miles Davis", title: "So What (Remaster)", trackNumber: 1, discNumber: 1, durationSeconds: 545, format: "flac", bitrate: 1024, dateAdded: .now)],
            updatedPlaylists: [],
            deletedTrackIDs: [], deletedAlbumIDs: [], deletedArtistIDs: [],
            newSyncCursor: "cursor-2"
        )
        let secondProvider = StubProvider(snapshot: snapshot(), delta: delta)
        try await LibrarySyncService.synchronize(server, using: secondProvider, context: context)

        let albums = try context.fetch(FetchDescriptor<Album>())
        let tracks = try context.fetch(FetchDescriptor<Track>())

        // Upsert en place : le titre existant est mis à jour (pas dupliqué), le nouvel album ajouté.
        #expect(albums.count == 2)
        #expect(tracks.count == 2)
        let renamed = tracks.first { $0.remoteID == "t1" }
        #expect(renamed?.title == "So What (Remaster)")
        #expect(server.syncCursor == "cursor-2")
    }

    @Test func serverFavoritesAreMergedAsUnionWithoutClearingLocal() async throws {
        let context = makeContext()
        let server = ServerAccount(name: "Démo", type: .jellyfin)
        context.insert(server)

        // Le serveur marque l'album "al1" et le titre "t1" comme favoris (lecture seule).
        let favorites = RemoteFavorites(albumIDs: ["al1"], trackIDs: ["t1"], artistIDs: [])
        let provider = StubProvider(snapshot: snapshot(), delta: emptyDelta(), favorites: favorites)
        try await LibrarySyncService.synchronize(server, using: provider, context: context)

        let albums = try context.fetch(FetchDescriptor<Album>())
        let tracks = try context.fetch(FetchDescriptor<Track>())

        // Les favoris serveur sont appliqués localement…
        #expect(albums.first { $0.remoteID == "al1" }?.isFavorite == true)
        #expect(tracks.first { $0.remoteID == "t1" }?.isFavorite == true)
        // …et seulement eux (t2 n'était pas favori côté serveur).
        #expect(tracks.first { $0.remoteID == "t2" }?.isFavorite == false)

        // UNION : un favori posé localement et ABSENT du serveur ne doit JAMAIS être retiré par une synchro.
        let t2 = try #require(tracks.first { $0.remoteID == "t2" })
        t2.isFavorite = true
        t2.favoriteDate = .now
        try context.save()

        // 2ᵉ synchro (delta vide) : le serveur ne connaît toujours que al1/t1.
        let provider2 = StubProvider(snapshot: snapshot(), delta: emptyDelta(), favorites: favorites)
        try await LibrarySyncService.synchronize(server, using: provider2, context: context)

        let tracksAfter = try context.fetch(FetchDescriptor<Track>())
        #expect(tracksAfter.first { $0.remoteID == "t1" }?.isFavorite == true)   // favori serveur conservé
        #expect(tracksAfter.first { $0.remoteID == "t2" }?.isFavorite == true)   // favori local préservé (union)
    }
}
