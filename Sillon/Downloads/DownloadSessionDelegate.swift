import Foundation

/// Délégué de la session de téléchargement de fond. **Non isolé** : ses callbacks arrivent sur une
/// file de fond gérée par `URLSession`. Il ne fait que le strict nécessaire de façon synchrone
/// (déplacer le fichier reçu, qui serait sinon supprimé au retour), puis délègue les mises à jour de
/// modèles au `DownloadManager` sur le `MainActor`.
final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate {
    weak var manager: DownloadManager?

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let payload = DownloadManager.decode(downloadTask.taskDescription) else { return }
        let destination = URL(fileURLWithPath: payload.destinationPath)
        let fm = FileManager.default
        let trackID = payload.trackID

        do {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try? fm.removeItem(at: destination) }
            try fm.moveItem(at: location, to: destination)
            Task { @MainActor [weak self] in
                self?.manager?.finalize(trackID: trackID, destinationPath: destination.path)
            }
        } catch {
            let message = error.localizedDescription
            Task { @MainActor [weak self] in
                self?.manager?.markFailed(trackID: trackID, message: message)
            }
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        // On identifie le morceau par le trackID encodé dans `taskDescription` (fiable), PAS par
        // `taskIdentifier` qui est réutilisé entre tâches/sessions → progression sur le mauvais morceau.
        guard let payload = DownloadManager.decode(downloadTask.taskDescription) else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let trackID = payload.trackID
        Task { @MainActor [weak self] in
            self?.manager?.updateProgress(trackID: trackID, fraction: fraction)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }   // le succès est traité dans didFinishDownloadingTo
        if (error as NSError).code == NSURLErrorCancelled { return }
        guard let payload = DownloadManager.decode(task.taskDescription) else { return }
        let trackID = payload.trackID
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.manager?.markFailed(trackID: trackID, message: message)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak self] in
            self?.manager?.flushBackgroundCompletion()
        }
    }
}
