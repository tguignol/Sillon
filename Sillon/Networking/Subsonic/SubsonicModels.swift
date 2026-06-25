import Foundation

// MARK: - DTOs Subsonic / OpenSubsonic
//
// Toutes les réponses Subsonic sont enveloppées dans un objet racine "subsonic-response"
// (confirmé par la spécification, en mode `f=json`). Le contenu utile change de nom selon
// l'endpoint appelé (artists, albumList2, album, searchResult3, playlists, playlist) ; on les
// modélise tous comme optionnels dans `SubsonicResponseBody` plutôt que de créer une réponse
// par endpoint, ce qui suffit pour le sous-ensemble d'endpoints de la Phase 1.

struct SubsonicResponseEnvelope: Decodable, Sendable {
    let subsonicResponse: SubsonicResponseBody
    enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }
}

struct SubsonicResponseBody: Decodable, Sendable {
    let status: String
    let version: String?
    let error: SubsonicAPIError?
    let artists: SubsonicArtistsIndex?
    let albumList2: SubsonicAlbumList2?
    let album: SubsonicAlbumDetail?
    let searchResult3: SubsonicSearchResult3?
    let playlists: SubsonicPlaylists?
    let playlist: SubsonicPlaylistDetail?
    let lyricsList: SubsonicLyricsList?
}

/// Réponse `getLyricsBySongId` (extension OpenSubsonic). `start` en millisecondes ; un tableau
/// `structuredLyrics` peut contenir plusieurs langues/variantes (on prend la première).
struct SubsonicLyricsList: Decodable, Sendable {
    struct Structured: Decodable, Sendable {
        struct Line: Decodable, Sendable {
            let start: Int?      // millisecondes ; absent => non synchronisé
            let value: String?
        }
        let synced: Bool?
        let offset: Int?         // ms, décalage global appliqué à chaque start (défaut 0)
        let line: [Line]?
    }
    let structuredLyrics: [Structured]?
}

struct SubsonicAPIError: Decodable, Sendable {
    let code: Int
    let message: String?
}

struct SubsonicArtist: Decodable, Sendable {
    let id: String
    let name: String
    let coverArt: String?
}

struct SubsonicArtistsIndex: Decodable, Sendable {
    struct Index: Decodable, Sendable {
        let name: String?
        let artist: [SubsonicArtist]?
    }
    let index: [Index]?
}

struct SubsonicAlbum: Decodable, Sendable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    let coverArt: String?
    let year: Int?
    let created: String?
}

struct SubsonicAlbumList2: Decodable, Sendable {
    let album: [SubsonicAlbum]?
}

/// ReplayGain OpenSubsonic (sous-objet `replayGain` de chaque song). Champ du cœur OpenSubsonic,
/// présent dès que `openSubsonic: true` ; absent (=> nil) sur Subsonic legacy. Gains en dB,
/// peaks en ratio linéaire. Navidrome omet les champs à zéro/absents (omitempty) => nil = inconnu.
struct SubsonicReplayGain: Decodable, Sendable {
    let trackGain: Double?
    let albumGain: Double?
    let trackPeak: Double?
    let albumPeak: Double?
    let baseGain: Double?      // dB, ex. Opus output gain ; à sommer quel que soit le mode
    let fallbackGain: Double?  // dB, repli côté client quand le gain du mode est absent
}

struct SubsonicSong: Decodable, Sendable {
    let id: String
    let title: String
    let album: String?
    let albumId: String?
    let artist: String?
    let track: Int?
    let discNumber: Int?
    let duration: Int?    // secondes (confirmé : entier, pas de fraction)
    let suffix: String?   // extension/codec d'origine, ex: "flac", "mp3"
    let bitRate: Int?
    let created: String?
    let replayGain: SubsonicReplayGain?
}

struct SubsonicAlbumDetail: Decodable, Sendable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    let coverArt: String?
    let year: Int?
    let created: String?
    let song: [SubsonicSong]?
}

struct SubsonicSearchResult3: Decodable, Sendable {
    let artist: [SubsonicArtist]?
    let album: [SubsonicAlbum]?
    let song: [SubsonicSong]?
}

struct SubsonicPlaylistSummary: Decodable, Sendable {
    let id: String
    let name: String
}

struct SubsonicPlaylists: Decodable, Sendable {
    let playlist: [SubsonicPlaylistSummary]?
}

struct SubsonicPlaylistDetail: Decodable, Sendable {
    let id: String
    let name: String
    let entry: [SubsonicSong]?
}
