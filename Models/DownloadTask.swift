import Foundation
import SwiftData

/// Entrée de file de téléchargement.
///
/// Distinct de `Track.downloadStatus` : `Track` porte un statut "résumé" simple (pratique pour l'UI liste),
/// tandis que `DownloadTask` porte le détail nécessaire à la reprise après coupure / relance de l'app
/// (progression, erreur, identifiant de la URLSessionDownloadTask sous-jacente). Le `DownloadManager`
/// (introduit à l'étape "Téléchargement") réconcilie les deux à chaque lancement de l'app.
@Model
final class DownloadTask {
    @Attribute(.unique) var id: UUID
    var trackID: String   // correspond à Track.id
    var status: DownloadStatus
    var progressFraction: Double   // 0...1
    var localFileURLString: String?
    var errorMessage: String?
    var queuedAt: Date
    var startedAt: Date?
    var completedAt: Date?

    /// Identifiant de la URLSessionDownloadTask (taskIdentifier) au moment de la création,
    /// pour ré-associer la tâche système après relance de l'app via
    /// `URLSession(configuration:delegate:delegateQueue:)` en mode background.
    var urlSessionTaskIdentifier: Int?

    init(trackID: String) {
        self.id = UUID()
        self.trackID = trackID
        self.status = .queued
        self.progressFraction = 0
        self.queuedAt = .now
    }
}
