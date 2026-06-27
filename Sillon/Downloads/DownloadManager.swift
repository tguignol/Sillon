import Foundation
import SwiftUI
import SwiftData

/// Gestionnaire de téléchargements offline-first.
///
/// Conçu autour d'une `URLSession` **en arrière-plan** (`background(withIdentifier:)`) : les
/// téléchargements se poursuivent quand l'app est suspendue et reprennent après relance. Le délégué
/// (`DownloadSessionDelegate`, non isolé) reçoit les callbacks sur une file de fond, déplace le
/// fichier reçu dans l'arborescence serveur de façon **synchrone** (le fichier temporaire est
/// supprimé au retour du callback), puis bascule sur le `MainActor` pour mettre à jour SwiftData.
///
/// Concurrence : la classe est `@MainActor` (elle touche le `ModelContext` de l'UI) ; le délégué est
/// une classe séparée non isolée qui ne fait que déplacer le fichier puis rappeler le manager via
/// `Task { @MainActor in … }`. La destination de chaque tâche est encodée dans `taskDescription`
/// (donc disponible au délégué sans accès à SwiftData, y compris après relance de l'app).
@MainActor
@Observable
final class DownloadManager {
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let sessionIdentifier: String
    @ObservationIgnored private let delegate = DownloadSessionDelegate()

    /// Fournisseurs authentifiés mis en cache (un par serveur) pour résoudre les URLs de téléchargement.
    @ObservationIgnored private var providers: [UUID: any ServerProvider] = [:]

    /// Stocké par l'`UIApplicationDelegateAdaptor` (iOS) : à appeler quand tous les événements de la
    /// session de fond ont été traités après un réveil de l'app.
    @ObservationIgnored var backgroundCompletionHandler: (() -> Void)?

    @ObservationIgnored private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.allowsCellularAccess = true
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()

    /// Dernière instance créée — utilisée par l'`UIApplicationDelegate` (iOS) pour router le
    /// completion handler du réveil en arrière-plan vers le bon manager.
    @ObservationIgnored static weak var shared: DownloadManager?

    init(container: ModelContainer, sessionIdentifier: String = "app.sillon.downloads") {
        self.container = container
        self.sessionIdentifier = sessionIdentifier
        delegate.manager = self
        // Force la création de la session dès le lancement : la session de fond rejoue alors les
        // événements en attente (téléchargements terminés pendant que l'app était fermée).
        _ = session
        Self.shared = self
    }

    private var context: ModelContext { container.mainContext }

    // MARK: - File d'attente

    /// Met un morceau en file de téléchargement. No-op pour les serveurs `.local` (déjà sur disque).
    func enqueue(_ track: Track) async {
        guard let server = track.server else { return }
        guard server.type != .local else { return }
        // Déjà téléchargé ou déjà en cours : on ne reprogramme pas.
        if track.downloadStatus == .downloaded || track.downloadStatus == .downloading || track.downloadStatus == .queued {
            return
        }

        let destination = DownloadFileLayout.destination(for: track)
        let trackID = track.id

        do {
            let provider = try provider(for: server)
            let url = try await provider.downloadURL(for: track.remoteID)

            let task = session.downloadTask(with: url)
            task.taskDescription = Self.encode(trackID: trackID, destinationPath: destination.path)

            // Modèle de file : on réutilise un DownloadTask existant pour ce morceau s'il y en a un.
            let record = existingTask(for: trackID) ?? {
                let new = DownloadTask(trackID: trackID)
                context.insert(new)
                return new
            }()
            record.status = .downloading
            record.progressFraction = 0
            record.errorMessage = nil
            record.startedAt = .now
            record.urlSessionTaskIdentifier = task.taskIdentifier
            record.localFileURLString = destination.path

            track.downloadStatus = .downloading

            task.resume()
            try? context.save()
        } catch {
            markFailed(trackID: trackID, message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Met tout un album en file (morceaux non encore téléchargés).
    func enqueueAlbum(_ album: Album) async {
        for track in album.tracks where track.downloadStatus != .downloaded {
            await enqueue(track)
        }
    }

    /// Annule le téléchargement d'un morceau et nettoie son état.
    func cancel(_ track: Track) {
        let trackID = track.id
        session.getAllTasks { tasks in
            for task in tasks where Self.decode(task.taskDescription)?.trackID == trackID {
                task.cancel()
            }
        }
        if let record = existingTask(for: trackID) {
            context.delete(record)
        }
        track.downloadStatus = .notDownloaded
        track.localFileURLString = nil
        try? context.save()
    }

    /// Supprime le fichier téléchargé d'un morceau (le repasse en "non téléchargé").
    func removeDownload(_ track: Track) {
        if let path = track.localFileURLString {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        }
        if let record = existingTask(for: track.id) { context.delete(record) }
        track.downloadStatus = .notDownloaded
        track.localFileURLString = nil
        try? context.save()
    }

    /// URL de lecture locale si le morceau est téléchargé et présent sur disque (offline-first).
    /// Le lecteur (commit suivant) l'utilisera en priorité avant de retomber sur le streaming.
    func localURL(for track: Track) -> URL? {
        if let url = Self.directLocalURL(track) { return url }
        // Cette copie n'a pas de fichier local : une copie du même titre sur un autre serveur l'est
        // peut-être (ex. après un changement de priorité serveur) → on lit alors ce fichier hors-ligne.
        for copy in DuplicateResolver.trackCopies(of: track, in: context) where copy !== track {
            if let url = Self.directLocalURL(copy) { return url }
        }
        return nil
    }

    private static func directLocalURL(_ track: Track) -> URL? {
        guard track.downloadStatus == .downloaded, let path = track.localFileURLString else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Réconcilie l'état après relance : un DownloadTask marqué "en cours" sans tâche système vivante
    /// correspondante est considéré comme interrompu (repassé en échec, reprenable par l'utilisateur).
    func reconcileOnLaunch() {
        session.getAllTasks { tasks in
            let liveIDs = Set(tasks.map(\.taskIdentifier))
            Task { @MainActor in
                let records = (try? self.context.fetch(FetchDescriptor<DownloadTask>())) ?? []
                for record in records where record.status == .downloading {
                    if let tid = record.urlSessionTaskIdentifier, liveIDs.contains(tid) { continue }
                    // Pas de tâche vivante : si le fichier final existe déjà, c'est un succès passé.
                    if let path = record.localFileURLString, FileManager.default.fileExists(atPath: path) {
                        self.finalize(trackID: record.trackID, destinationPath: path)
                    } else {
                        record.status = .failed
                        record.errorMessage = LanguageManager.string("Téléchargement interrompu")
                        self.track(for: record.trackID)?.downloadStatus = .failed
                    }
                }
                try? self.context.save()
            }
        }
    }

    // MARK: - Callbacks (appelés sur le MainActor depuis le délégué)

    func updateProgress(trackID: String, fraction: Double) {
        guard let record = existingTask(for: trackID) else { return }
        record.progressFraction = fraction
        if record.status != .downloading {
            record.status = .downloading
            track(for: trackID)?.downloadStatus = .downloading
        }
    }

    /// Appelé après que le délégué a déplacé le fichier à `destinationPath` (de façon synchrone).
    func finalize(trackID: String, destinationPath: String) {
        guard let track = track(for: trackID) else { return }
        track.downloadStatus = .downloaded
        track.localFileURLString = destinationPath
        if let record = existingTask(for: trackID) {
            record.status = .downloaded
            record.progressFraction = 1
            record.completedAt = .now
            record.localFileURLString = destinationPath
            record.errorMessage = nil
        }
        try? context.save()
    }

    func markFailed(trackID: String, message: String) {
        track(for: trackID)?.downloadStatus = .failed
        if let record = existingTask(for: trackID) {
            record.status = .failed
            record.errorMessage = message
        }
        try? context.save()
    }

    func flushBackgroundCompletion() {
        backgroundCompletionHandler?()
        backgroundCompletionHandler = nil
    }

    // MARK: - Lookups

    private func provider(for server: ServerAccount) throws -> any ServerProvider {
        if let existing = providers[server.id] { return existing }
        let created = try ServerProviderFactory.makeProvider(for: server)
        providers[server.id] = created
        return created
    }

    private func existingTask(for trackID: String) -> DownloadTask? {
        let descriptor = FetchDescriptor<DownloadTask>(predicate: #Predicate { $0.trackID == trackID })
        return try? context.fetch(descriptor).first
    }


    func track(for trackID: String) -> Track? {
        let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.id == trackID })
        return try? context.fetch(descriptor).first
    }

    // MARK: - Encodage de la destination dans taskDescription

    nonisolated private static let separator = "\u{1}"

    nonisolated static func encode(trackID: String, destinationPath: String) -> String {
        "\(trackID)\(separator)\(destinationPath)"
    }

    nonisolated static func decode(_ description: String?) -> (trackID: String, destinationPath: String)? {
        guard let parts = description?.components(separatedBy: separator), parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }
}

extension EnvironmentValues {
    /// Injecté à la racine de l'app. Valeur par défaut inerte pour les Previews (jamais utilisée
    /// pour de vrais téléchargements hors app).
    @Entry var downloadManager: DownloadManager? = nil
}
