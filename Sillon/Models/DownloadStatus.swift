import Foundation

/// État de disponibilité locale d'un morceau.
enum DownloadStatus: String, Codable, Hashable, Sendable {
    case notDownloaded
    case queued
    case downloading
    case downloaded
    case failed

    var label: String {
        switch self {
        case .notDownloaded: LanguageManager.string("Non téléchargé")
        case .queued: LanguageManager.string("En attente")
        case .downloading: LanguageManager.string("Téléchargement…")
        case .downloaded: LanguageManager.string("Téléchargé")
        case .failed: LanguageManager.string("Échec")
        }
    }

    var systemImageName: String {
        switch self {
        case .notDownloaded: "icloud.and.arrow.down"
        case .queued: "clock"
        case .downloading: "arrow.down.circle"
        case .downloaded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}
