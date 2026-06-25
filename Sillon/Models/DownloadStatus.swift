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
        case .notDownloaded: "Non téléchargé"
        case .queued: "En attente"
        case .downloading: "Téléchargement…"
        case .downloaded: "Téléchargé"
        case .failed: "Échec"
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
