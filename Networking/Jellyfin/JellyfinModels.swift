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
    let Type: String?
    let Codec: String?
    let BitRate: Int?
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

    var audioCodec: String? {
        MediaStreams?.first(where: { $0.Type == "Audio" })?.Codec
    }

    var audioBitRate: Int? {
        MediaStreams?.first(where: { $0.Type == "Audio" })?.BitRate
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
