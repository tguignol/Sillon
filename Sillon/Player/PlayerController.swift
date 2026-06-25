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

    /// Échéance de la minuterie de veille (nil = désactivée). L'UI s'en sert pour afficher le décompte.
    private(set) var sleepTimerEndDate: Date?

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

    // MARK: Crossfade (fondu enchaîné)
    // Deux "decks" (player + mixer de fondu) sommés avant l'EQ permettent de faire jouer deux morceaux
    // en parallèle et de croiser leurs gains. À crossfadeDuration == 0, on n'utilise QUE deckA.player
    // (= le `player` ci-dessus) sur le graphe gapless mono-node existant : zéro régression.

    /// Un deck = un nœud de lecture + son mixer de fondu + l'état du morceau qu'il porte.
    /// Classe (sémantique de référence) pour muter l'état via le deck actif sans copie.
    @MainActor private final class Deck {
        let player: AVAudioPlayerNode
        let fadeMixer: AVAudioMixerNode
        var file: AVAudioFile?
        var trackIndex: Int?
        // Chaque deck est `stop()` avant (re)planification → son `sampleTime` repart de 0 ; le temps
        // courant du deck est donc `seekFrame + sampleTime` (pas besoin de mémoriser un frame de départ).
        var seekFrame: AVAudioFramePosition = 0
        var fileLength: AVAudioFramePosition = 0
        var sampleRate: Double = 44_100
        var replayGain: Float = 1.0                // gain ReplayGain du morceau du deck (player.volume)
        init(player: AVAudioPlayerNode, fadeMixer: AVAudioMixerNode) {
            self.player = player
            self.fadeMixer = fadeMixer
        }
    }

    private enum CrossfadeState {
        case idle
        /// Fondu en cours : `fromIsA` = deck sortant. La progression est dérivée de l'avancée réelle de
        /// lecture du deck entrant (horloge audio), pas d'une horloge murale → robuste au gel du RunLoop
        /// (arrière-plan/interruption) : si l'audio se fige, le fondu se fige aussi puis reprend net.
        case fading(fromIsA: Bool, duration: TimeInterval)
    }

    @ObservationIgnored private let deckA: Deck
    @ObservationIgnored private let deckB: Deck
    @ObservationIgnored private var activeIsA = true
    @ObservationIgnored private let sumMixer = AVAudioMixerNode()
    @ObservationIgnored private var renderFormat: AVAudioFormat?   // format aval figé en mode crossfade
    @ObservationIgnored private var crossfadeGraphActive = false   // quel graphe physique est câblé
    @ObservationIgnored private var crossfadeState: CrossfadeState = .idle
    @ObservationIgnored private var fadeRampTimer: Timer?

    private var activeDeck: Deck { activeIsA ? deckA : deckB }
    private var idleDeck: Deck { activeIsA ? deckB : deckA }

    /// Durée de fondu (s), relue à la demande depuis les réglages. 0 = enchaînement gapless actuel.
    private var crossfadeDuration: TimeInterval {
        max(0, UserDefaults.standard.double(forKey: "crossfadeDuration"))
    }

    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var sleepTimer: Timer?
    @ObservationIgnored private var sleepFadeTimer: Timer?
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
        // deckA réutilise le `player` existant (le chemin gapless l'emploie tel quel) ; deckB est le
        // second nœud de fondu. Les fadeMixers/sumMixer ne sont câblés qu'en mode crossfade.
        let fadeA = AVAudioMixerNode()
        let fadeB = AVAudioMixerNode()
        let playerB = AVAudioPlayerNode()
        self.deckA = Deck(player: player, fadeMixer: fadeA)
        self.deckB = Deck(player: playerB, fadeMixer: fadeB)
        engine.attach(player)
        engine.attach(playerB)
        engine.attach(fadeA)
        engine.attach(fadeB)
        engine.attach(sumMixer)
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
            pauseNodes()
            isPlaying = false
            stopTicker()
        } else {
            startEngineIfNeeded()
            resumeNodes()
            isPlaying = true
            startTicker()
        }
        updateNowPlayingInfo()
        savePlaybackState()
    }

    private func pauseNodes() {
        if crossfadeGraphActive {
            // Mettre en pause pendant un fondu dériverait l'horloge murale du fondu : on le termine net.
            if case .fading = crossfadeState { finishCrossfade() }
            activeDeck.player.pause()
        } else {
            player.pause()
        }
    }

    private func resumeNodes() {
        if crossfadeGraphActive {
            activeDeck.player.play()
        } else {
            player.play()
        }
    }

    func next() {
        guard currentIndex + 1 < queue.count else { return }
        endActiveCrossfadeIfNeeded()
        currentIndex += 1
        Task { await loadCurrent(autoplay: true) }
    }

    func previous() {
        // Reprise au début si on est à plus de 3 s, sinon morceau précédent.
        if currentTime > 3 || currentIndex == 0 {
            seek(to: 0)
        } else {
            endActiveCrossfadeIfNeeded()
            currentIndex -= 1
            Task { await loadCurrent(autoplay: true) }
        }
    }

    /// Coupe net un fondu en cours AVANT un changement de morceau explicite (mode crossfade), de façon
    /// synchrone : invalide le timer de rampe et fige les decks avant la fenêtre `await` de loadCurrent.
    private func endActiveCrossfadeIfNeeded() {
        if crossfadeGraphActive { abortCrossfade() }
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
        // Si on passe à « répéter ce titre » pendant un fondu, le terminer net : le morceau entrant
        // (déjà devenu courant) reste seul à plein gain ; prepareNextDeck (gardé par .one) ne préparera
        // plus de suivant. Sinon le fondu finirait et sauterait au titre suivant au lieu de répéter.
        if repeatMode == .one, case .fading = crossfadeState {
            finishCrossfade()
        }
    }

    /// Saute à un morceau précis de la file.
    func jump(to index: Int) {
        guard queue.indices.contains(index) else { return }
        endActiveCrossfadeIfNeeded()
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

    // MARK: - Minuterie de veille

    /// `true` si une minuterie de veille est armée.
    var isSleepTimerActive: Bool { sleepTimerEndDate != nil }

    /// Arme la minuterie pour s'arrêter dans `minutes` minutes (fondu de sortie puis pause).
    func setSleepTimer(minutes: Int) {
        armSleepTimer(after: TimeInterval(max(1, minutes) * 60))
    }

    /// Arme la minuterie pour s'arrêter à la fin du morceau courant (temps restant).
    func setSleepTimerEndOfTrack() {
        armSleepTimer(after: max(1, duration - currentTime))
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate(); sleepTimer = nil
        sleepFadeTimer?.invalidate(); sleepFadeTimer = nil
        sleepTimerEndDate = nil
        engine.mainMixerNode.outputVolume = max(0, min(1, volume))   // au cas où un fondu était en cours
    }

    private func armSleepTimer(after seconds: TimeInterval) {
        sleepTimer?.invalidate()
        sleepFadeTimer?.invalidate(); sleepFadeTimer = nil
        sleepTimerEndDate = Date().addingTimeInterval(seconds)
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.sleepTimerFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        sleepTimer = timer
    }

    private func sleepTimerFired() {
        sleepTimer = nil
        sleepTimerEndDate = nil
        guard isPlaying else { return }
        fadeOutAndPause()
    }

    /// Fondu de sortie (~4 s) sur le volume mixer, puis pause, puis restauration du volume utilisateur
    /// (pour que la prochaine lecture ne démarre pas muette).
    private func fadeOutAndPause() {
        let userVolume = max(0, min(1, volume))
        let steps = 40
        var step = 0
        sleepFadeTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] t in
            Task { @MainActor in
                guard let self else { t.invalidate(); return }
                step += 1
                let progress = Float(step) / Float(steps)
                self.engine.mainMixerNode.outputVolume = userVolume * (1 - progress)
                if step >= steps {
                    t.invalidate()
                    self.sleepFadeTimer = nil
                    if self.isPlaying { self.togglePlayPause() }   // pause propre (gapless/crossfade)
                    self.engine.mainMixerNode.outputVolume = userVolume   // restaure pour la reprise
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sleepFadeTimer = timer
    }

    func seek(to seconds: TimeInterval) {
        guard let file = audioFile else { return }
        if crossfadeGraphActive {
            seekCrossfade(to: seconds, file: file)
        } else {
            seekGapless(to: seconds, file: file)
        }
    }

    private func seekGapless(to seconds: TimeInterval, file: AVAudioFile) {
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

    /// Seek en mode crossfade : annule un fondu en cours et re-planifie le segment sur le deck actif.
    private func seekCrossfade(to seconds: TimeInterval, file: AVAudioFile) {
        abortCrossfade()
        let deck = activeDeck
        let wasPlaying = isPlaying
        let frame = AVAudioFramePosition(max(0, seconds) * deck.sampleRate)
        let remaining = file.length - frame
        deck.seekFrame = frame
        deck.player.stop()
        guard remaining > 0 else { handlePlaybackEnded(); return }

        scheduleGeneration += 1
        let generation = scheduleGeneration
        let index = currentIndex
        deck.player.scheduleSegment(file, startingFrame: frame, frameCount: AVAudioFrameCount(remaining), at: nil,
                                    completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.handleTrackEnded(index: index, generation: generation) }
        }
        currentTime = seconds
        if wasPlaying {
            startEngineIfNeeded()
            deck.player.play()
            isPlaying = true
            startTicker()
        }
        updateNowPlayingInfo()
        savePlaybackState()
        Task { await prepareNextDeck(generation: generation) }
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
        if case .fading = crossfadeState { abortCrossfade() }   // éviter un clic en plein fondu
        let format = audioFile?.processingFormat
        let newEQ = AVAudioUnitEQ(numberOfBands: bandCount)
        engine.attach(newEQ)
        // Recâble l'EQ selon le graphe courant (sumMixer en amont en crossfade, player en gapless).
        if crossfadeGraphActive, let renderFmt = renderFormat {
            engine.connect(sumMixer, to: newEQ, format: renderFmt)
            engine.connect(newEQ, to: engine.mainMixerNode, format: renderFmt)
        } else if let format {
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
            if crossfadeDuration > 0 {
                startCrossfadeLoad(file: file, track: track, autoplay: autoplay)
            } else {
                startGaplessLoad(file: file, track: track, autoplay: autoplay)
            }
            updateNowPlayingInfo()
            Task { await loadArtwork(for: track) }
            savePlaybackState()
        } catch {
            errorMessage = "Fichier audio illisible."
            isPlaying = false
        }
    }

    /// Chemin gapless mono-node (comportement d'origine, inchangé) : un seul `player`, pré-planification
    /// du suivant sur le même nœud.
    private func startGaplessLoad(file: AVAudioFile, track: Track, autoplay: Bool) {
        activeIsA = true            // en gapless, `player` == deckA == deck actif : on garde la cohérence
        abortCrossfade()
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
        Task { await scheduleNextGapless(generation: generation) }
    }

    /// Chemin crossfade : démarre le morceau sur deckA, prépare le suivant sur deckB (joué et fondu
    /// à l'approche de la fin par `maybeStartCrossfade`).
    private func startCrossfadeLoad(file: AVAudioFile, track: Track, autoplay: Bool) {
        activeIsA = true
        abortCrossfade()
        let deck = deckA
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

        deck.file = file
        deck.trackIndex = currentIndex
        deck.sampleRate = sampleRate
        deck.seekFrame = 0
        deck.fileLength = file.length
        deckB.file = nil
        deckB.trackIndex = nil
        deckB.player.stop()

        connectGraph(format: file.processingFormat)   // câble le graphe crossfade + l'entrée de deckA
        let factor = replayGainFactor(for: track)
        deck.replayGain = factor
        deck.player.volume = factor
        deck.fadeMixer.outputVolume = 1
        deckB.fadeMixer.outputVolume = 0
        startEngineIfNeeded()

        deck.player.stop()
        scheduleGeneration += 1
        let generation = scheduleGeneration
        let index = currentIndex
        deck.player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.handleTrackEnded(index: index, generation: generation) }
        }
        if autoplay {
            deck.player.play()
            isPlaying = true
            startTicker()
        }
        Task { await prepareNextDeck(generation: generation) }
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
        if crossfadeDuration > 0 {
            connectCrossfadeGraph(activeFileFormat: format)
        } else {
            connectGaplessGraph(format: format)
        }
    }

    private func disconnectAudioGraph() {
        for node in [deckA.player, deckB.player, deckA.fadeMixer, deckB.fadeMixer, sumMixer, eq] {
            engine.disconnectNodeOutput(node)
        }
    }

    /// Graphe gapless mono-node : `player → eq → mainMixer` au format du fichier (comportement actuel).
    private func connectGaplessGraph(format: AVAudioFormat) {
        crossfadeGraphActive = false
        disconnectAudioGraph()
        engine.connect(player, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
    }

    /// Graphe crossfade : `deckA.fadeMixer/deckB.fadeMixer → sumMixer → eq → mainMixer` au format de
    /// rendu figé ; le deck actif est câblé au format de son fichier (le deck inactif l'est dans
    /// `prepareNextDeck`). `sumMixer` reste à gain 1.0 pour que le niveau d'un morceau seul soit
    /// IDENTIQUE au mode gapless ; le fondu equal-power (cos²+sin²=1) garde la puissance constante et,
    /// pour deux morceaux décorrélés, le pic de sommation reste ≈ unité.
    private func connectCrossfadeGraph(activeFileFormat: AVAudioFormat) {
        // Format de rendu TOUJOURS valide : taux matériel s'il est négocié (>0), sinon le taux du
        // fichier actif (jamais 0). Stéréo float standard ; les fadeMixers convertissent chaque deck.
        // Le moteur peut ne pas être encore démarré ici (outputFormat = 0 Hz) → repli sur le fichier.
        let hwRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let rate = hwRate > 0 ? hwRate : activeFileFormat.sampleRate
        let renderFmt = renderFormat ?? AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        renderFormat = renderFmt
        crossfadeGraphActive = true
        disconnectAudioGraph()
        engine.connect(deckA.fadeMixer, to: sumMixer, format: renderFmt)
        engine.connect(deckB.fadeMixer, to: sumMixer, format: renderFmt)
        engine.connect(sumMixer, to: eq, format: renderFmt)
        engine.connect(eq, to: engine.mainMixerNode, format: renderFmt)
        sumMixer.outputVolume = 1.0
        engine.connect(activeDeck.player, to: activeDeck.fadeMixer, format: activeFileFormat)
    }

    /// (Re)câble l'amont d'un deck (player → fadeMixer) au format de son fichier.
    private func connectDeckInput(_ deck: Deck, fileFormat: AVAudioFormat) {
        engine.disconnectNodeOutput(deck.player)
        engine.connect(deck.player, to: deck.fadeMixer, format: fileFormat)
    }

    // MARK: - ReplayGain (normalisation du volume)

    /// Applique le gain ReplayGain du morceau courant. On l'applique sur `player.volume` (gain
    /// par-source) plutôt que sur un nœud post-mix : c'est correct par-source et survivra au
    /// crossfade (chaque deck portera son propre gain). Le volume utilisateur reste sur le mainMixer,
    /// l'EQ sur l'eq — aucune des responsabilités n'est mélangée.
    private func applyReplayGain() {
        let factor = replayGainFactor(for: currentTrack)
        if crossfadeGraphActive {
            activeDeck.replayGain = factor
            activeDeck.player.volume = factor
            // Rafraîchir aussi le deck entrant déjà préparé (sauf en plein fondu, pour ne pas créer un
            // saut de gain audible sur un morceau en cours de fondu).
            if case .idle = crossfadeState, let idx = idleDeck.trackIndex, queue.indices.contains(idx) {
                let inFactor = replayGainFactor(for: queue[idx])
                idleDeck.replayGain = inFactor
                idleDeck.player.volume = inFactor
            }
        } else {
            player.volume = factor   // gapless : deckA.player
        }
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

    // MARK: - Crossfade (fondu enchaîné)

    /// Temps courant d'un deck : `seekFrame + sampleTime` (le deck est `stop()` avant planification,
    /// donc son `sampleTime` repart de 0), borné à la durée du fichier.
    private func deckCurrentTime(_ deck: Deck) -> TimeInterval {
        guard let nodeTime = deck.player.lastRenderTime,
              let playerTime = deck.player.playerTime(forNodeTime: nodeTime) else { return currentTime }
        let frames = deck.seekFrame + playerTime.sampleTime
        let dur = deck.sampleRate > 0 ? Double(deck.fileLength) / deck.sampleRate : duration
        return min(dur, max(0, Double(frames) / deck.sampleRate))
    }

    /// Durée de fondu effective, bornée à la moitié de chaque morceau (sortant et entrant) pour ne
    /// jamais fondre plus longtemps qu'un demi-titre.
    private func effectiveFadeDuration() -> TimeInterval {
        let inDur = idleDeck.file.map { Double($0.length) / max(1, idleDeck.sampleRate) } ?? crossfadeDuration
        return min(crossfadeDuration, max(0, duration / 2), max(0, inDur / 2))
    }

    /// Déclenche un fondu quand on approche de la fin du morceau courant, si le suivant est prêt.
    private func maybeStartCrossfade() {
        guard case .idle = crossfadeState else { return }
        guard crossfadeDuration > 0, repeatMode != .one else { return }
        guard currentIndex + 1 < queue.count else { return }          // pas de fondu sur le dernier titre
        guard idleDeck.file != nil, idleDeck.trackIndex == currentIndex + 1 else { return }   // suivant prêt
        let dur = effectiveFadeDuration()
        guard dur > 0, duration - currentTime <= dur else { return }
        beginCrossfade(duration: dur)
    }

    /// Démarre le fondu : joue le deck entrant, bascule l'identité du morceau (index/titre/durée) au
    /// début du fondu, et lance la rampe equal-power.
    private func beginCrossfade(duration dur: TimeInterval) {
        guard let inFile = idleDeck.file, idleDeck.trackIndex == currentIndex + 1 else { return }
        let incoming = idleDeck
        let fromIsA = activeIsA

        incoming.player.play()   // le deck entrant a été planifié (gain 0) dans prepareNextDeck

        // Bascule ATOMIQUE de l'identité du morceau au DÉBUT du fondu (barre/titre = morceau entrant).
        // La garde `index == currentIndex` de handleTrackEnded rejette alors la complétion tardive du sortant.
        activeIsA.toggle()
        currentIndex += 1
        audioFile = inFile
        sampleRate = incoming.sampleRate
        duration = Double(incoming.fileLength) / max(1, incoming.sampleRate)
        currentTime = 0
        seekFrame = 0
        if let track = currentTrack {
            currentFormatDescription = Self.formatDescription(for: inFile, track: track)
            Task { await loadArtwork(for: track) }
        }
        updateNowPlayingInfo()
        savePlaybackState()

        crossfadeState = .fading(fromIsA: fromIsA, duration: dur)
        startFadeRamp()
    }

    private func startFadeRamp() {
        fadeRampTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateFadeRamp() }
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeRampTimer = timer
    }

    private func updateFadeRamp() {
        guard case let .fading(fromIsA, dur) = crossfadeState else { return }
        let outDeck = fromIsA ? deckA : deckB
        let inDeck = fromIsA ? deckB : deckA
        // Le deck entrant joue depuis 0 : son temps courant EST le temps écoulé du fondu.
        let elapsed = deckCurrentTime(inDeck)
        let x = dur > 0 ? min(1, max(0, elapsed / dur)) : 1
        let (gOut, gIn) = equalPowerGains(x)
        outDeck.fadeMixer.outputVolume = gOut
        inDeck.fadeMixer.outputVolume = gIn
        if x >= 1 { finishCrossfade() }
    }

    /// Rampe à puissance constante (cos²+sin²=1) : pas de creux de -3 dB au milieu du fondu.
    private func equalPowerGains(_ x: Double) -> (out: Float, in: Float) {
        let c = x * .pi / 2
        return (Float(cos(c)), Float(sin(c)))
    }

    /// Termine le fondu : arrête/​libère le deck sortant, gains nets, prépare le morceau d'après.
    private func finishCrossfade() {
        guard case let .fading(fromIsA, _) = crossfadeState else { return }
        fadeRampTimer?.invalidate()
        fadeRampTimer = nil
        crossfadeState = .idle
        let outgoing = fromIsA ? deckA : deckB
        outgoing.player.stop()
        outgoing.file = nil
        outgoing.trackIndex = nil
        activeDeck.fadeMixer.outputVolume = 1
        outgoing.fadeMixer.outputVolume = 0
        Task { await prepareNextDeck(generation: scheduleGeneration) }
    }

    /// Annule un fondu en cours : remet le deck actif à plein, libère/​arrête le deck inactif.
    private func abortCrossfade() {
        fadeRampTimer?.invalidate()
        fadeRampTimer = nil
        crossfadeState = .idle
        activeDeck.fadeMixer.outputVolume = 1
        idleDeck.fadeMixer.outputVolume = 0
        idleDeck.player.stop()
        idleDeck.file = nil
        idleDeck.trackIndex = nil
    }

    /// Pré-planifie le morceau suivant sur le deck inactif (muet jusqu'au fondu). Le fadeMixer convertit
    /// les fréquences hétérogènes, donc pas de garde de sample-rate ici (contrairement au gapless).
    private func prepareNextDeck(generation: Int) async {
        guard generation == scheduleGeneration, crossfadeGraphActive, repeatMode != .one else { return }
        let nextIndex = currentIndex + 1
        guard nextIndex < queue.count else { return }
        let deck = idleDeck
        guard deck.trackIndex != nextIndex else { return }   // déjà prêt
        let nextTrack = queue[nextIndex]
        guard let url = await resolveURL(for: nextTrack) else { return }
        guard generation == scheduleGeneration, crossfadeGraphActive else { return }
        guard let file = try? AVAudioFile(forReading: url) else { return }

        deck.player.stop()
        connectDeckInput(deck, fileFormat: file.processingFormat)
        deck.file = file
        deck.trackIndex = nextIndex
        deck.sampleRate = file.processingFormat.sampleRate
        deck.seekFrame = 0
        deck.fileLength = file.length
        let factor = replayGainFactor(for: nextTrack)
        deck.replayGain = factor
        deck.player.volume = factor
        deck.fadeMixer.outputVolume = 0   // muet jusqu'au début du fondu
        deck.player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.handleTrackEnded(index: nextIndex, generation: generation) }
        }
        // On ne play() pas encore : beginCrossfade démarrera ce deck au bon moment.
    }

    /// Appelé depuis l'UI quand la durée de crossfade change. Si on franchit la frontière 0↔>0 pendant
    /// la lecture, on recâble le graphe en rechargeant le morceau courant à sa position.
    func refreshCrossfade() {
        guard audioFile != nil, (crossfadeDuration > 0) != crossfadeGraphActive else { return }
        let pos = currentTime
        let wasPlaying = isPlaying
        Task {
            await loadCurrent(autoplay: wasPlaying)
            if pos > 1 { seek(to: pos) }
        }
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
        if crossfadeGraphActive {
            currentTime = deckCurrentTime(activeDeck)
            maybeStartCrossfade()
        } else if let nodeTime = player.lastRenderTime, let playerTime = player.playerTime(forNodeTime: nodeTime) {
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
