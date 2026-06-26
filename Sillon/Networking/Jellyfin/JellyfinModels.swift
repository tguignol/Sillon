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
    /// Conteneur de fichier (ex: "flac", "wav", "m4a", "mp3"). Propriété racine renvoyée par défaut
    /// pour un item audio. C'est « le format utilisé », plus fiable que le codec brut.
    let Container: String?
    /// Chemin du fichier sur le serveur (demandé via `Fields=Path`). Sert uniquement de repli pour
    /// déduire l'extension si `Container` est absent ; jamais affiché ni stocké tel quel.
    let Path: String?
    /// Gain de normalisation ReplayGain (dB, gain piste déjà prêt). Propriété racine de l'item,
    /// PAS dans MediaSources. Nullable : absent si le fichier n'a pas de tag ReplayGain et que la
    /// tâche serveur « Audio Normalization » (scan LUFS) n'a pas tourné. Pas de peak ni de gain album.
    let NormalizationGain: Double?

    var audioCodec: String? {
        MediaStreams?.first(where: { $0.StreamType == "Audio" })?.Codec
    }

    /// Format de fichier à afficher (« le format utilisé ») : on privilégie le conteneur
    /// (flac, wav, m4a, mp3…) plutôt que le codec brut, car ce dernier est trompeur pour le PCM
    /// (un WAV est rapporté « pcm_s24le »). Le conteneur MP4/M4A pouvant abriter AAC *ou* ALAC,
    /// on tranche alors avec le codec. Repli : extension du chemin, puis codec.
    var fileFormat: String? {
        let containerRaw = Container?.split(separator: ",").first.map(String.init)
        let pathExt = Path.map { ($0 as NSString).pathExtension }
        let container = (containerRaw ?? pathExt)?.trimmingCharacters(in: .whitespaces).lowercased()
        let codec = audioCodec?.trimmingCharacters(in: .whitespaces).lowercased()
        guard let container, !container.isEmpty else { return audioCodec }
        if ["m4a", "m4b", "mp4", "mp4a", "mka", "mov"].contains(container), let codec, !codec.isEmpty {
            return codec   // désambiguïse le conteneur MP4 : « alac » ou « aac »
        }
        return container
    }

    var audioBitRate: Int? {
        // Jellyfin renvoie le débit en bits/s ; l'app affiche des kbps (comme Subsonic) → /1000.
        MediaStreams?.first(where: { $0.StreamType == "Audio" })?.BitRate.map { $0 / 1000 }
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
