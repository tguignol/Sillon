import Foundation
import SwiftUI
import SwiftData
import AVFoundation

/// Contrôleur de lecture audio : moteur `AVAudioEngine` (chaîne `player → EQ → mixer`) + file de
/// lecture + transport. Offline-first : si un morceau est téléchargé, on lit le fichier local ;
/// sinon on récupère le flux (sans transcodage) dans un cache temporaire avant lecture.
///
/// L'EQ (`AVAudioUnitEQ`) applique l'état persistant `EQSettings` et reste modifiable en direct.
///
/// Note Phase 1 : la lecture passe par `AVAudioFile` (local), donc un morceau non téléchargé est
/// d'abord récupéré en entier avant de démarrer (latence). Le vrai streaming réseau *gapless* avec
/// EQ est un raffinement de Phase 2 — cf. Docs/DECISIONS.md.
@MainActor
@Observable
final class PlayerController {
    // MARK: État exposé à l'UI
    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int = 0
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var errorMessage: String?

    /// Magnitudes de spectre temps réel (0…1, graves → aigus) pour la visualisation autour de la pochette.
    private(set) var spectrum: [Float] = Array(repeating: 0, count: 48)

    /// Volume de sortie de l'app (0…1), appliqué au mixer du moteur.
    var volume: Float = 1.0 {
        didSet { engine.mainMixerNode.outputVolume = max(0, min(1, volume)) }
    }

    var currentTrack: Track? {
        queue.indices.contains(currentIndex) ? queue[currentIndex] : nil
    }

    // MARK: Dépendances
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private weak var downloadManager: DownloadManager?
    @ObservationIgnored private var providers: [UUID: any ServerProvider] = [:]

    // MARK: Moteur audio
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private(set) var eq: AVAudioUnitEQ
    @ObservationIgnored private var audioFile: AVAudioFile?
    @ObservationIgnored private var sampleRate: Double = 44_100
    @ObservationIgnored private var seekFrame: AVAudioFramePosition = 0
    @ObservationIgnored private var scheduleGeneration = 0
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private let analyzer = AudioSpectrumAnalyzer(bandCount: 48)
    @ObservationIgnored private var tapInstalled = false

    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer, downloadManager: DownloadManager? = nil) {
        self.container = container
        self.downloadManager = downloadManager
        let settings = EQSettingsStore.load(container.mainContext)
        self.eq = AVAudioUnitEQ(numberOfBands: settings.bandCount)
        engine.attach(player)
        engine.attach(eq)
        EQBands.apply(gainsDB: settings.gainsDB, isEnabled: settings.isEnabled, to: eq)
        engine.mainMixerNode.outputVolume = volume
    }

    // MARK: - Transport

    /// Démarre la lecture d'une file à partir d'un index donné.
    func play(queue tracks: [Track], startAt index: Int) {
        guard tracks.indices.contains(index) else { return }
        queue = tracks
        currentIndex = index
        Task { await loadCurrent(autoplay: true) }
    }

    func togglePlayPause() {
        guard audioFile != nil else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            stopTicker()
        } else {
            startEngineIfNeeded()
            player.play()
            isPlaying = true
            startTicker()
        }
    }

    func next() {
        guard currentIndex + 1 < queue.count else { return }
        currentIndex += 1
        Task { await loadCurrent(autoplay: true) }
    }

    func previous() {
        // Reprise au début si on est à plus de 3 s, sinon morceau précédent.
        if currentTime > 3 || currentIndex == 0 {
            seek(to: 0)
        } else {
            currentIndex -= 1
            Task { await loadCurrent(autoplay: true) }
        }
    }

    func skip(by seconds: TimeInterval) {
        seek(to: min(max(0, currentTime + seconds), duration))
    }

    func seek(to seconds: TimeInterval) {
        guard let file = audioFile else { return }
        let wasPlaying = isPlaying
        let frame = AVAudioFramePosition(max(0, seconds) * sampleRate)
        let remaining = file.length - frame
        seekFrame = frame
        player.stop()
        guard remaining > 0 else { handlePlaybackEnded(); return }

        scheduleGeneration += 1
        let generation = scheduleGeneration
        player.scheduleSegment(file, startingFrame: frame, frameCount: AVAudioFrameCount(remaining), at: nil,
                               completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.handleScheduleCompleted(generation) }
        }
        currentTime = seconds
        if wasPlaying {
            startEngineIfNeeded()
            player.play()
            isPlaying = true
            startTicker()
        }
    }

    // MARK: - Favori (le cœur du lecteur)

    func toggleFavoriteOfCurrent() {
        guard let track = currentTrack else { return }
        track.isFavorite.toggle()
        track.favoriteDate = track.isFavorite ? .now : nil
        try? context.save()
    }

    // MARK: - Égaliseur

    /// Réapplique l'état EQ persistant au moteur (et recrée l'unité si le nombre de bandes a changé).
    func refreshEQ() {
        let settings = EQSettingsStore.load(context)
        if eq.bands.count != settings.bandCount {
            rebuildEQ(bandCount: settings.bandCount)
        }
        EQBands.apply(gainsDB: settings.gainsDB, isEnabled: settings.isEnabled, to: eq)
    }

    private func rebuildEQ(bandCount: Int) {
        let format = audioFile?.processingFormat
        let newEQ = AVAudioUnitEQ(numberOfBands: bandCount)
        engine.attach(newEQ)
        if let format {
            engine.connect(player, to: newEQ, format: format)
            engine.connect(newEQ, to: engine.mainMixerNode, format: format)
        }
        engine.detach(eq)
        eq = newEQ
    }

    // MARK: - Chargement

    private func loadCurrent(autoplay: Bool) async {
        guard let track = currentTrack else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = await resolveURL(for: track) else {
            errorMessage = "Lecture impossible (fichier introuvable)."
            isPlaying = false
            return
        }
        do {
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            sampleRate = file.processingFormat.sampleRate
            duration = Double(file.length) / sampleRate
            seekFrame = 0
            currentTime = 0

            connectGraph(format: file.processingFormat)
            startEngineIfNeeded()

            player.stop()
            scheduleGeneration += 1
            let generation = scheduleGeneration
            player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in self?.handleScheduleCompleted(generation) }
            }
            if autoplay {
                player.play()
                isPlaying = true
                startTicker()
            }
        } catch {
            errorMessage = "Fichier audio illisible."
            isPlaying = false
        }
    }

    /// Offline-first : fichier local si téléchargé, sinon récupération du flux dans un cache temporaire.
    private func resolveURL(for track: Track) async -> URL? {
        if let local = downloadManager?.localURL(for: track) { return local }
        guard let server = track.server else { return nil }
        // Serveur local : l'identifiant distant est déjà un chemin de fichier.
        if server.type == .local { return URL(fileURLWithPath: track.remoteID) }
        do {
            let provider = try provider(for: server)
            let streamURL = try await provider.streamURL(for: track.remoteID)
            let cache = cacheURL(for: track)
            if FileManager.default.fileExists(atPath: cache.path) { return cache }
            let (tmp, _) = try await URLSession.shared.download(from: streamURL)
            try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: cache)
            try FileManager.default.moveItem(at: tmp, to: cache)
            return cache
        } catch {
            return nil
        }
    }

    private func cacheURL(for track: Track) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SillonStreamCache", isDirectory: true)
        let name = DownloadFileLayout.sanitize(track.id) + "." + (track.format ?? "audio")
        return dir.appendingPathComponent(name)
    }

    // MARK: - Moteur

    private func connectGraph(format: AVAudioFormat) {
        engine.disconnectNodeOutput(player)
        engine.disconnectNodeOutput(eq)
        engine.connect(player, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
    }

    private func startEngineIfNeeded() {
        configureAudioSession()
        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }
        installSpectrumTapIfNeeded()
    }

    private func installSpectrumTapIfNeeded() {
        guard !tapInstalled else { return }
        analyzer.installTap(on: engine.mainMixerNode) { [weak self] bands in
            // Callback sur le thread audio : on rebascule sur le MainActor pour publier.
            Task { @MainActor in self?.applySpectrum(bands) }
        }
        tapInstalled = true
    }

    /// Attaque rapide / chute lente : donne un mouvement de VU-mètre agréable plutôt que saccadé.
    private func applySpectrum(_ bands: [Float]) {
        var updated = spectrum
        let n = min(updated.count, bands.count)
        for i in 0..<n {
            let target = bands[i]
            updated[i] = target > updated[i] ? target : updated[i] * 0.80 + target * 0.20
        }
        spectrum = updated
    }

    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        #endif
    }

    // MARK: - Fin de lecture / ticker

    private func handleScheduleCompleted(_ generation: Int) {
        // Ignore les complétions des planifications remplacées (seek, changement de morceau).
        guard generation == scheduleGeneration else { return }
        handlePlaybackEnded()
    }

    private func handlePlaybackEnded() {
        if currentIndex + 1 < queue.count {
            next()
        } else {
            isPlaying = false
            currentTime = duration
            stopTicker()
        }
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard isPlaying else { return }
        if let nodeTime = player.lastRenderTime, let playerTime = player.playerTime(forNodeTime: nodeTime) {
            currentTime = min(duration, Double(seekFrame + playerTime.sampleTime) / sampleRate)
        }
    }

    // MARK: - Providers

    private func provider(for server: ServerAccount) throws -> any ServerProvider {
        if let existing = providers[server.id] { return existing }
        let created = try ServerProviderFactory.makeProvider(for: server)
        providers[server.id] = created
        return created
    }
}

extension EnvironmentValues {
    @Entry var playerController: PlayerController? = nil
}
