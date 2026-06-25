import Foundation
import SwiftUI
import SwiftData
import AVFoundation
import MediaPlayer
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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

    /// Forme d'onde temporelle (-1…1) pour le style oscilloscope.
    private(set) var waveform: [Float] = Array(repeating: 0, count: 128)

    /// Description technique du flux réellement lu (codec · fréquence · profondeur · débit).
    private(set) var currentFormatDescription: String?

    /// Volume de sortie de l'app (0…1), appliqué au mixer du moteur.
    var volume: Float = 1.0 {
        didSet { engine.mainMixerNode.outputVolume = max(0, min(1, volume)) }
    }

    var currentTrack: Track? {
        queue.indices.contains(currentIndex) ? queue[currentIndex] : nil
    }

    enum RepeatMode: String, CaseIterable {
        case off, all, one
        var systemImage: String { self == .one ? "repeat.1" : "repeat" }
        var isActive: Bool { self != .off }
    }

    private(set) var isShuffled = false
    var repeatMode: RepeatMode = .off
    @ObservationIgnored private var originalQueue: [Track] = []

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
    // Gapless : `playerTime.sampleTime` court en continu à travers les fichiers pré-planifiés ;
    // on mémorise l'instant (en frames) où le morceau courant a commencé, et la longueur du fichier.
    @ObservationIgnored private var currentTrackStartFrame: AVAudioFramePosition = 0
    @ObservationIgnored private var currentFileLength: AVAudioFramePosition = 0
    @ObservationIgnored private var nextFile: AVAudioFile?
    @ObservationIgnored private var nextPreparedIndex: Int?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private let analyzer = AudioSpectrumAnalyzer(bandCount: 48)
    @ObservationIgnored private var tapInstalled = false
    @ObservationIgnored private var currentArtwork: MPMediaItemArtwork?
    @ObservationIgnored private var artworkToken = UUID()
    @ObservationIgnored private var lastSaveTime: TimeInterval = 0

    private var context: ModelContext { container.mainContext }

    // MARK: Réglages de lecture (miroir des @AppStorage de PlaybackSettingsView, lus à la demande)
    // PlayerController est @Observable et n'observe pas @AppStorage (réservé aux vues) : il relit
    // ces préférences via UserDefaults au moment d'appliquer le gain (mêmes clés que l'UI).

    private var replayGainMode: ReplayGainMode {
        ReplayGainMode(rawValue: UserDefaults.standard.string(forKey: "replayGainMode") ?? "") ?? .off
    }
    private var replayGainClipProtection: Bool {
        // `object(forKey:)` pour distinguer « absent » (défaut true) de « false explicite ».
        UserDefaults.standard.object(forKey: "replayGainClipProtection") as? Bool ?? true
    }
    private var replayGainPreampDB: Double {
        UserDefaults.standard.double(forKey: "replayGainPreampDB")   // 0 par défaut
    }

    init(container: ModelContainer, downloadManager: DownloadManager? = nil) {
        self.container = container
        self.downloadManager = downloadManager
        let settings = EQSettingsStore.load(container.mainContext)
        self.eq = AVAudioUnitEQ(numberOfBands: settings.bandCount)
        engine.attach(player)
        engine.attach(eq)
        EQBands.apply(gainsDB: settings.gainsDB, isEnabled: settings.isEnabled, to: eq)
        engine.mainMixerNode.outputVolume = volume
        setupRemoteCommands()
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
        updateNowPlayingInfo()
        savePlaybackState()
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

    // MARK: - File d'attente / aléatoire / répétition

    /// Bascule la lecture aléatoire. Le morceau en cours reste en tête ; le reste est mélangé
    /// (ou l'ordre d'origine restauré à la désactivation).
    func toggleShuffle() {
        guard let current = currentTrack else { isShuffled.toggle(); return }
        if isShuffled {
            isShuffled = false
            if !originalQueue.isEmpty {
                queue = originalQueue
                currentIndex = queue.firstIndex { $0.id == current.id } ?? 0
                originalQueue = []
            }
        } else {
            isShuffled = true
            originalQueue = queue
            var rest = queue.filter { $0.id != current.id }
            rest.shuffle()
            queue = [current] + rest
            currentIndex = 0
        }
        rescheduleFromCurrentPosition()
    }

    /// Ré-établit la planification (morceau courant + suivant pré-planifié) à la position actuelle.
    /// Utilisé après une modification de la file pour que le bon morceau suivant joue en gapless.
    private func rescheduleFromCurrentPosition() {
        guard audioFile != nil else { return }
        seek(to: currentTime)
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    /// Saute à un morceau précis de la file.
    func jump(to index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        Task { await loadCurrent(autoplay: true) }
    }

    /// Réordonne la file (glisser-déposer) en conservant le morceau en cours.
    func moveQueue(from source: IndexSet, to destination: Int) {
        let currentID = currentTrack?.id
        queue.move(fromOffsets: source, toOffset: destination)
        if let currentID { currentIndex = queue.firstIndex { $0.id == currentID } ?? currentIndex }
        if isShuffled { originalQueue = [] }   // l'ordre manuel prime sur la restauration shuffle
        rescheduleFromCurrentPosition()
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
        currentTrackStartFrame = 0       // `stop()` remet `sampleTime` à zéro
        currentFileLength = remaining     // seules les frames restantes sont planifiées
        nextFile = nil
        nextPreparedIndex = nil
        guard remaining > 0 else { handlePlaybackEnded(); return }

        scheduleGeneration += 1
        let generation = scheduleGeneration
        let index = currentIndex
        player.scheduleSegment(file, startingFrame: frame, frameCount: AVAudioFrameCount(remaining), at: nil,
                               completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.handleTrackEnded(index: index, generation: generation) }
        }
        currentTime = seconds
        if wasPlaying {
            startEngineIfNeeded()
            player.play()
            isPlaying = true
            startTicker()
        }
        updateNowPlayingInfo()
        savePlaybackState()
        Task { await scheduleNextGapless(generation: generation) }
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
            currentTrackStartFrame = 0
            currentFileLength = file.length
            nextFile = nil
            nextPreparedIndex = nil
            currentFormatDescription = Self.formatDescription(for: file, track: track)

            connectGraph(format: file.processingFormat)
            applyReplayGain()           // gain de normalisation du morceau courant (neutre si désactivé)
            startEngineIfNeeded()

            player.stop()
            scheduleGeneration += 1
            let generation = scheduleGeneration
            let index = currentIndex
            player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in self?.handleTrackEnded(index: index, generation: generation) }
            }
            if autoplay {
                player.play()
                isPlaying = true
                startTicker()
            }
            updateNowPlayingInfo()
            Task { await loadArtwork(for: track) }
            savePlaybackState()
            Task { await scheduleNextGapless(generation: generation) }
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

    // MARK: - ReplayGain (normalisation du volume)

    /// Applique le gain ReplayGain du morceau courant. On l'applique sur `player.volume` (gain
    /// par-source) plutôt que sur un nœud post-mix : c'est correct par-source et survivra au
    /// crossfade (chaque deck portera son propre gain). Le volume utilisateur reste sur le mainMixer,
    /// l'EQ sur l'eq — aucune des responsabilités n'est mélangée.
    private func applyReplayGain() {
        player.volume = replayGainFactor(for: currentTrack)
    }

    /// Réapplique immédiatement le réglage ReplayGain au morceau en cours (appelé depuis l'UI réglages).
    func refreshReplayGain() {
        applyReplayGain()
    }

    /// Facteur linéaire (0…1+) pour un morceau selon le mode + pré-ampli + anti-clipping.
    /// Délègue le calcul pur à `ReplayGain.linearFactor` (testé unitairement).
    private func replayGainFactor(for track: Track?) -> Float {
        guard let track else { return 1.0 }
        return ReplayGain.linearFactor(
            mode: replayGainMode,
            trackGain: track.trackGain, trackPeak: track.trackPeak,
            albumGain: track.albumGain, albumPeak: track.albumPeak,
            albumRelGain: track.album?.albumGain, albumRelPeak: track.album?.albumPeak,
            fallbackGain: track.fallbackGain,
            preampDB: replayGainPreampDB,
            clipProtection: replayGainClipProtection
        )
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
        analyzer.installTap(on: engine.mainMixerNode) { [weak self] bands, wave in
            // Callback sur le thread audio : on rebascule sur le MainActor pour publier.
            Task { @MainActor in self?.applySpectrum(bands, waveform: wave) }
        }
        tapInstalled = true
    }

    /// Attaque rapide / chute lente : donne un mouvement de VU-mètre agréable plutôt que saccadé.
    private func applySpectrum(_ bands: [Float], waveform wave: [Float]) {
        var updated = spectrum
        let n = min(updated.count, bands.count)
        for i in 0..<n {
            let target = bands[i]
            updated[i] = target > updated[i] ? target : updated[i] * 0.80 + target * 0.20
        }
        spectrum = updated
        waveform = wave
    }

    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        #endif
    }

    // MARK: - Fin de lecture / ticker

    /// Appelé quand le fichier d'un morceau (à l'index donné) a fini d'être joué.
    private func handleTrackEnded(index: Int, generation: Int) {
        guard generation == scheduleGeneration else { return }   // planification remplacée (seek/changement)
        guard index == currentIndex else { return }              // complétion d'un fichier déjà dépassé

        // Cas gapless : le morceau suivant a été pré-planifié et joue déjà sans blanc.
        if let nextFile, nextPreparedIndex == currentIndex + 1, repeatMode != .one {
            advanceGapless(to: nextFile, newIndex: currentIndex + 1, generation: generation)
            return
        }
        handlePlaybackEnded()
    }

    /// Bascule sur le morceau suivant déjà en cours de lecture (aucun arrêt du moteur).
    private func advanceGapless(to file: AVAudioFile, newIndex: Int, generation: Int) {
        currentTrackStartFrame += currentFileLength
        currentIndex = newIndex
        audioFile = file
        currentFileLength = file.length
        duration = Double(file.length) / sampleRate
        seekFrame = 0
        currentTime = 0
        nextFile = nil
        nextPreparedIndex = nil
        // Le gapless ne repasse pas par loadCurrent : sans ça le morceau suivant garderait le gain
        // du précédent. On réapplique le ReplayGain du nouveau morceau courant.
        applyReplayGain()
        if let track = currentTrack {
            currentFormatDescription = Self.formatDescription(for: file, track: track)
            Task { await loadArtwork(for: track) }
        }
        updateNowPlayingInfo()
        savePlaybackState()
        Task { await scheduleNextGapless(generation: generation) }
    }

    /// Pré-planifie le morceau suivant pour une transition sans blanc, si possible (même fréquence
    /// d'échantillonnage, fichier accessible). Sinon repli sur le rechargement classique à la transition.
    private func scheduleNextGapless(generation: Int) async {
        guard generation == scheduleGeneration, repeatMode != .one else { return }
        let nextIndex = currentIndex + 1
        guard nextIndex < queue.count, nextPreparedIndex != nextIndex else { return }
        let nextTrack = queue[nextIndex]
        guard let url = await resolveURL(for: nextTrack) else { return }
        guard generation == scheduleGeneration else { return }
        guard let file = try? AVAudioFile(forReading: url),
              file.processingFormat.sampleRate == sampleRate else { return }

        player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.handleTrackEnded(index: nextIndex, generation: generation) }
        }
        nextFile = file
        nextPreparedIndex = nextIndex
    }

    private func handlePlaybackEnded() {
        switch repeatMode {
        case .one:
            Task { await loadCurrent(autoplay: true) }
        case .all:
            if currentIndex + 1 < queue.count {
                next()
            } else {
                currentIndex = 0
                Task { await loadCurrent(autoplay: true) }
            }
        case .off:
            if currentIndex + 1 < queue.count {
                next()
            } else {
                isPlaying = false
                currentTime = duration
                stopTicker()
                updateNowPlayingInfo()
            }
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
            // `sampleTime` court à travers les fichiers pré-planifiés → on retranche le départ du morceau.
            let frames = seekFrame + (playerTime.sampleTime - currentTrackStartFrame)
            currentTime = min(duration, max(0, Double(frames) / sampleRate))
        }
        // Sauvegarde périodique de la position pour la reprise au lancement.
        if currentTime - lastSaveTime >= 8 {
            lastSaveTime = currentTime
            savePlaybackState()
        }
    }

    // MARK: - Providers

    private func provider(for server: ServerAccount) throws -> any ServerProvider {
        if let existing = providers[server.id] { return existing }
        let created = try ServerProviderFactory.makeProvider(for: server)
        providers[server.id] = created
        return created
    }

    // MARK: - Now Playing (écran verrouillé / Centre de contrôle / AirPods)

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == false { self?.togglePlayPause() } }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == true { self?.togglePlayPause() } }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: e.positionTime) }
            return .success
        }
    }

    /// Met à jour les métadonnées « en cours de lecture » du système (titre, artiste, durée, position).
    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let artist = track.artistNameSnapshot ?? track.album?.artist?.name {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let album = track.album?.title {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let currentArtwork {
            info[MPMediaItemPropertyArtwork] = currentArtwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Charge la pochette pour l'écran verrouillé (best-effort, asynchrone).
    private func loadArtwork(for track: Track) async {
        currentArtwork = nil
        let token = UUID()
        artworkToken = token
        guard let server = track.server, let path = track.album?.coverArtRemotePath else { return }
        do {
            let provider = try provider(for: server)
            guard let url = try await provider.coverArtURL(for: path, preferredSize: 600) else { return }
            let (data, _) = try await URLSession.shared.data(from: url)
            guard artworkToken == token else { return }   // morceau changé entre-temps
            #if os(iOS)
            if let image = UIImage(data: data) {
                currentArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                updateNowPlayingInfo()
            }
            #elseif os(macOS)
            if let image = NSImage(data: data) {
                currentArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                updateNowPlayingInfo()
            }
            #endif
        } catch {
            // Pas de pochette : on garde les métadonnées texte.
        }
    }

    // MARK: - Format réel & reprise de session

    /// Décrit le flux réellement lu : codec · fréquence d'échantillonnage · profondeur · débit.
    nonisolated static func formatDescription(for file: AVAudioFile, track: Track) -> String {
        var parts: [String] = []
        if let format = track.format, !format.isEmpty { parts.append(format.uppercased()) }
        let asbd = file.fileFormat.streamDescription.pointee
        let sampleRate = asbd.mSampleRate > 0 ? asbd.mSampleRate : file.processingFormat.sampleRate
        if sampleRate > 0 { parts.append(String(format: "%.1f kHz", sampleRate / 1000)) }
        if asbd.mBitsPerChannel > 0 { parts.append("\(asbd.mBitsPerChannel) bit") }
        if let bitrate = track.bitrate, bitrate > 0 { parts.append("\(bitrate) kbps") }
        return parts.joined(separator: " · ")
    }

    private static let savedStateKey = "sillon.lastPlaybackState"

    private func savePlaybackState() {
        guard !queue.isEmpty, currentTrack != nil else { return }
        let state = SavedPlaybackState(trackIDs: queue.map(\.id), currentIndex: currentIndex, position: currentTime)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.savedStateKey)
        }
    }

    /// Restaure la dernière session (file + morceau + position) au lancement, **en pause**.
    func restoreLastSession() {
        guard queue.isEmpty,   // ne pas écraser une lecture déjà en cours
              let data = UserDefaults.standard.data(forKey: Self.savedStateKey),
              let state = try? JSONDecoder().decode(SavedPlaybackState.self, from: data),
              !state.trackIDs.isEmpty
        else { return }

        let ids = state.trackIDs
        let descriptor = FetchDescriptor<Track>(predicate: #Predicate { ids.contains($0.id) })
        let found = (try? context.fetch(descriptor)) ?? []
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let restored = state.trackIDs.compactMap { byID[$0] }
        guard !restored.isEmpty else { return }

        queue = restored
        currentIndex = min(max(0, state.currentIndex), restored.count - 1)
        Task {
            await loadCurrent(autoplay: false)
            if state.position > 1 { seek(to: state.position) }
        }
    }
}

/// État de lecture persisté (UserDefaults) pour la reprise au lancement.
private struct SavedPlaybackState: Codable {
    var trackIDs: [String]
    var currentIndex: Int
    var position: Double
}

extension EnvironmentValues {
    @Entry var playerController: PlayerController? = nil
}
