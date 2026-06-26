import Foundation

/// Mode de normalisation du volume ReplayGain / R128.
/// `.off` = aucun ajustement. `.track` = égalise piste à piste (idéal pour la lecture aléatoire).
/// `.album` = applique un gain commun à tout l'album (préserve la dynamique relative entre pistes).
enum ReplayGainMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case off
    case track
    case album

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off:   LanguageManager.string("Désactivé")
        case .track: LanguageManager.string("Piste")
        case .album: LanguageManager.string("Album")
        }
    }

    var systemImage: String {
        switch self {
        case .off:   "speaker.slash"
        case .track: "waveform"
        case .album: "square.stack"
        }
    }
}
