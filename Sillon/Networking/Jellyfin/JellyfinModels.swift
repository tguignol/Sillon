import Foundation

// MARK: - DTOs Jellyfin
//
// Sous-ensemble confirmé de la spécification OpenAPI Jellyfin (endpoints /Users/AuthenticateByName,
// /Users/{userId}/Items, /System/Info/Public). On ne modélise que les champs réellement utilisés ;
// `Decodable` ignore silencieusement les champs non déclarés, donc aucune perte de robustesse.
//
// Champs confirmés "par défaut" sur BaseItemDto (toujours présents pour un item audio) :
// Id, Name, AlbumId, Album, ArtistItems, AlbumArtist, ProductionYear, IndexNumber,
// ParentIndexNumber, RunTimeTicks, ImageTags.
// Champs confirmés "à la demande" via le paramètre `Fields` : DateCreated, MediaStreams, SortName
// — c'est pourquoi `JellyfinProvider` ajoute systématiquement `Fields=DateCreated,MediaStreams,SortName`
// à ses requêtes `/Items`.

struct JellyfinAuthenticationResult: Decodable, Sendable {
    struct UserInfo: Decodable, Sendable {
        let Id: String
        let Name: String?
    }
    let User: UserInfo
    let AccessToken: String
}

struct JellyfinPublicSystemInfo: Decodable, Sendable {
    let ServerName: String?
    let Version: String?
}

struct JellyfinNameId: Decodable, Sendable {
    let Name: String?
    let Id: String?
}

struct JellyfinMediaStream: Decodable, Sendable {
    /// "Audio", "Video", "Subtitle"... — on ne garde que les flux de type "Audio".
    /// Nommé `StreamType` plutôt que `Type` : Swift interdit un membre littéralement appelé
    /// `Type` (conflit avec la syntaxe de métatype `SomeType.Type`). On conserve le mapping
    /// vers la clé JSON réelle ("Type") via `CodingKeys`.
    let StreamType: String?
    let Codec: String?
    let BitRate: Int?

    enum CodingKeys: String, CodingKey {
        case StreamType = "Type"
        case Codec
        case BitRate
    }
}

struct JellyfinImageTags: Decodable, Sendable {
    let Primary: String?
}

struct JellyfinBaseItem: Decodable, Sendable {
    let Id: String
    let Name: String?
    let SortName: String?
    let AlbumId: String?
    let Album: String?
    let ArtistItems: [JellyfinNameId]?
    let AlbumArtist: String?
    let ProductionYear: Int?
    let IndexNumber: Int?         // numéro de piste
    let ParentIndexNumber: Int?   // numéro de disque
    let RunTimeTicks: Int64?      // durée en ticks .NET (1 tick = 100 ns), confirmé indépendamment de Jellyfin
    let DateCreated: String?      // ISO 8601
    let MediaStreams: [JellyfinMediaStream]?
    let ImageTags: JellyfinImageTags?
    let Genres: [String]?
    /// Gain de normalisation ReplayGain (dB, gain piste déjà prêt). Propriété racine de l'item,
    /// PAS dans MediaSources. Nullable : absent si le fichier n'a pas de tag ReplayGain et que la
    /// tâche serveur « Audio Normalization » (scan LUFS) n'a pas tourné. Pas de peak ni de gain album.
    let NormalizationGain: Double?

    var audioCodec: String? {
        MediaStreams?.first(where: { $0.StreamType == "Audio" })?.Codec
    }

    var audioBitRate: Int? {
        MediaStreams?.first(where: { $0.StreamType == "Audio" })?.BitRate
    }

    var durationSeconds: Double {
        guard let ticks = RunTimeTicks else { return 0 }
        return Double(ticks) / 10_000_000.0
    }
}

struct JellyfinItemsResponse: Decodable, Sendable {
    let Items: [JellyfinBaseItem]
    let TotalRecordCount: Int?
}

/// Réponse de `GET /Audio/{itemId}/Lyrics` (LyricDto). `Start` en ticks .NET (1 = 100 ns),
/// absent pour une ligne non synchronisée.
struct JellyfinLyricsResponse: Decodable, Sendable {
    struct Line: Decodable, Sendable {
        let Text: String?
        let Start: Int64?
    }
    let Lyrics: [Line]?
}
