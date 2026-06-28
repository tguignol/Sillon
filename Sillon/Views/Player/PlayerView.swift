import SwiftUI
#if os(iOS)
import AVKit
#endif

/// Écran lecteur plein écran : pochette entourée du *groove ring*, métadonnées, barre de progression
/// avec -10s/+10s, transport, cœur favori et sélecteur de sortie audio (AirPlay).
struct PlayerView: View {
    @Environment(\.playerController) private var player
    @Environment(\.dismiss) private var dismiss
    /// Fermeture personnalisée : utilisée quand le lecteur n'est PAS présenté en feuille/plein écran
    /// (cas macOS, affiché en ligne dans la zone de détail) — `dismiss` n'y ferait rien.
    var onClose: (() -> Void)? = nil
    @State private var showEQ = false
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var scrubTime: Double?
    @AppStorage("spectrumStyle") private var spectrumStyleRaw = SpectrumStyle.circularBars.rawValue

    private var spectrumStyle: SpectrumStyle {
        SpectrumStyle(rawValue: spectrumStyleRaw) ?? .circularBars
    }

    var body: some View {
        if let player, let track = player.currentTrack {
            // Le lecteur remplit toujours une zone DIMENSIONNÉE (plein écran iOS, zone de détail macOS) —
            // jamais une feuille qui se dimensionne sur son contenu — donc le GeometryReader la mesure
            // correctement. Largeur > hauteur = paysage → disposition deux colonnes (iPhone/iPad ET macOS).
            GeometryReader { proxy in
                styled(layout(track: track, player: player,
                              landscape: proxy.size.width > proxy.size.height,
                              size: proxy.size))
            }
        } else {
            ContentUnavailableView("Rien en lecture", systemImage: "music.note")
                .background(Palette.fondNoir)
        }
    }

    /// Habillage commun (fond, marges, feuilles modales) appliqué à la disposition choisie.
    private func styled(_ content: some View) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.l)
            .background(Palette.fondNoir)
            .animation(.easeInOut(duration: 0.25), value: showLyrics)
            .sheet(isPresented: $showEQ) { EQView() }
            .sheet(isPresented: $showQueue) { QueueView() }
    }

    /// Portrait : pile verticale (pochette/spectre en haut, contrôles dessous).
    /// Paysage : deux colonnes — pochette/spectre à gauche, métadonnées + transport + contrôles à droite.
    @ViewBuilder
    private func layout(track: Track, player: PlayerController, landscape: Bool, size: CGSize) -> some View {
        if landscape {
            // Tailles adaptées à la fenêtre : la pochette grandit avec l'espace disponible (plafonnée
            // pour rester élégante en très grande fenêtre), les contrôles gardent une largeur lisible et
            // centrée plutôt que de s'étirer d'un bord à l'autre. En petite fenêtre, la pochette rétrécit
            // naturellement (aspect-fit) jusqu'à disparaître — ce comportement reste inchangé.
            let coverMax = min(size.width * 0.45, size.height * 0.82, 640)
            let controlsMax = min(size.width * 0.46, 480)
            VStack(spacing: Spacing.l) {
                topBar
                HStack(spacing: Spacing.xl) {
                    mainVisual(track: track, player: player, maxSide: coverMax, landscape: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(spacing: Spacing.l) {
                        Spacer(minLength: 0)
                        titles(track: track)
                        progressSection(player: player)
                        transport(player: player)
                        volumeSection(player: player)
                        bottomRow(track: track, player: player)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: controlsMax)   // largeur lisible (barres non étirées)
                    .frame(maxWidth: .infinity)     // …centrée dans sa moitié
                }
            }
        } else {
            VStack(spacing: Spacing.xl) {
                topBar
                Spacer(minLength: 0)
                // Marge sous la pochette : les barres de spectre atteignent presque le bord du cadre ;
                // on sépare nettement du titre juste dessous (paroles : pas de marge, elles emplissent l'espace).
                mainVisual(track: track, player: player, maxSide: 344, landscape: false)
                    .padding(.bottom, showLyrics ? 0 : Spacing.xxl)
                titles(track: track)
                progressSection(player: player)
                transport(player: player)
                volumeSection(player: player)
                bottomRow(track: track, player: player)
                Spacer(minLength: 0)
            }
        }
    }

    /// Visuel central : pochette + spectre, ou paroles (à la Apple Music) — le transport reste
    /// accessible à côté/dessous sans fermer les paroles.
    @ViewBuilder
    private func mainVisual(track: Track, player: PlayerController, maxSide: CGFloat, landscape: Bool) -> some View {
        if showLyrics {
            if landscape {
                // Écran large : vignette d'album RÉDUITE en haut + paroles dessous (façon Apple Music / Android).
                VStack(spacing: Spacing.l) {
                    cover(track)
                        .frame(width: min(maxSide * 0.5, 240), height: min(maxSide * 0.5, 240))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCorner, style: .continuous))
                    LyricsView(track: track)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            } else {
                LyricsView(track: track)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        } else {
            artwork(track: track, player: player, maxSide: maxSide)
        }
    }

    /// Ferme le lecteur : repli en ligne sur macOS (`onClose`), sinon fermeture de la présentation (`dismiss`).
    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private var topBar: some View {
        HStack(spacing: Spacing.l) {
            Button { close() } label: {
                Image(systemName: "chevron.down").font(.title3).foregroundStyle(Palette.texteIvoire)
            }
            Spacer()
            Menu {
                Picker(selection: $spectrumStyleRaw) {
                    ForEach(SpectrumStyle.allCases) { style in
                        Label(style.label, systemImage: style.systemImage).tag(style.rawValue)
                    }
                } label: {
                    // Libellé via le passe-plat : le titre LocalizedStringKey d'un Picker ne suit pas
                    // notre redirection de langue sur macOS (en-tête affiché en anglais).
                    Text(LanguageManager.string("Visualisation"))
                }
                // `.inline` affiche les options directement dans le menu. Sans ça, macOS rend le Picker
                // comme un SOUS-MENU (« Visualisation › ») qui se ferme au clic → menu inutilisable.
                .pickerStyle(.inline)
            } label: {
                Image(systemName: spectrumStyle.systemImage).font(.title3).foregroundStyle(Palette.texteIvoire)
            }
            sleepTimerMenu
            Button { showEQ = true } label: {
                Image(systemName: "slider.vertical.3").font(.title3).foregroundStyle(Palette.signalTeal)
            }
        }
        .buttonStyle(.plain)
    }

    private var sleepTimerMenu: some View {
        Menu {
            if player?.isSleepTimerActive == true {
                Button("Désactiver la minuterie", systemImage: "moon.zzz.fill") { player?.cancelSleepTimer() }
                Divider()
            }
            ForEach([15, 30, 45, 60], id: \.self) { minutes in
                Button("\(minutes) min") { player?.setSleepTimer(minutes: minutes) }
            }
            Button("Fin du morceau", systemImage: "music.note") { player?.setSleepTimerEndOfTrack() }
        } label: {
            Image(systemName: player?.isSleepTimerActive == true ? "moon.zzz.fill" : "moon.zzz")
                .font(.title3)
                .foregroundStyle(player?.isSleepTimerActive == true ? Palette.accentCuivre : Palette.texteIvoire)
        }
    }

    @ViewBuilder
    private func artwork(track: Track, player: PlayerController, maxSide: CGFloat) -> some View {
        Group {
            switch spectrumStyle {
            case .off:
                // Sans spectre, ronde AGRANDIE : on occupe l'espace que prenait le spectre.
                cover(track).clipShape(Circle()).padding(Spacing.xs)
            case .offSquare:
                // Sans spectre, carrée à coins arrondis (artwork plein cadre).
                cover(track).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            default:
                ZStack {
                    SpectrumRingView(levels: player.spectrum, waveform: player.waveform, style: spectrumStyle)
                    cover(track).clipShape(Circle()).padding(28)   // serré par l'anneau de spectre
                }
            }
        }
        // Carré qui occupe l'espace proposé puis se plafonne à `maxSide` (qui s'adapte à la fenêtre).
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: maxSide, maxHeight: maxSide)
    }

    private func cover(_ track: Track) -> some View {
        CoverArtView(path: track.album?.coverArtRemotePath, server: track.server,
                     seed: track.album?.title ?? track.title, preferredSize: 600)
    }

    /// Info technique condensée (codec · fréquence, ex. « FLAC · 88,2 kHz »), affichée discrètement
    /// sous la barre de progression. Texte vert (teal), sans cadre.
    @ViewBuilder
    private func technicalInfo(player: PlayerController) -> some View {
        if let badge = player.currentQualityBadge, !badge.isEmpty {
            Text(badge)
                .font(Typo.technique)
                .foregroundStyle(Palette.signalTeal)
        }
    }

    private func titles(track: Track) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(track.title)
                .font(Typo.display)
                .foregroundStyle(Palette.texteIvoire)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(track.artistNameSnapshot ?? track.album?.artist?.name ?? "Artiste inconnu")
                .font(.headline)
                .foregroundStyle(.secondary)
            if let albumTitle = track.album?.title, !albumTitle.isEmpty {
                Text(albumTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
        }
    }

    private func progressSection(player: PlayerController) -> some View {
        VStack(spacing: Spacing.s) {
            Slider(
                value: Binding(
                    get: { scrubTime ?? player.currentTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(player.duration, 0.1)
            ) { editing in
                if !editing, let t = scrubTime { player.seek(to: t); scrubTime = nil }
            }
            .tint(Palette.accentCuivre)

            HStack {
                Text((scrubTime ?? player.currentTime).asTrackDuration)
                Spacer()
                Text(player.duration.asTrackDuration)
            }
            .font(Typo.technique)
            .foregroundStyle(.secondary)

            // Infos techniques (codec/fréquence/débit + sortie audio) juste sous la barre de progression.
            technicalInfo(player: player)
        }
    }

    private func transport(player: PlayerController) -> some View {
        HStack(spacing: Spacing.xl) {
            Button { player.skip(by: -10) } label: {
                Image(systemName: "gobackward.10")
            }
            Button { player.previous() } label: {
                Image(systemName: "backward.end.fill")
            }
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
            }
            .disabled(player.currentTrack == nil)
            Button { player.next() } label: {
                Image(systemName: "forward.end.fill")
            }
            Button { player.skip(by: 10) } label: {
                Image(systemName: "goforward.10")
            }
        }
        .font(.title2)
        .foregroundStyle(Palette.texteIvoire)
        .buttonStyle(.plain)
        .overlay(alignment: .center) {
            if player.isLoading {
                ProgressView().controlSize(.large)
            }
        }
    }

    private func volumeSection(player: PlayerController) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(get: { Double(player.volume) }, set: { player.volume = Float($0) }),
                in: 0...1
            )
            .tint(Palette.accentCuivre)
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func bottomRow(track: Track, player: PlayerController) -> some View {
        // Un Spacer entre chaque icône → répartition régulière sur toute la largeur.
        HStack(spacing: 0) {
            Button { player.toggleFavoriteOfCurrent() } label: {
                Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(track.isFavorite ? Palette.accentCuivre : Palette.texteIvoire)
            }
            Spacer()
            Button { player.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(player.isShuffled ? Palette.accentCuivre : Palette.texteIvoire)
            }
            Spacer()
            Button { player.cycleRepeatMode() } label: {
                Image(systemName: player.repeatMode.systemImage)
                    .foregroundStyle(player.repeatMode.isActive ? Palette.accentCuivre : Palette.texteIvoire)
            }
            Spacer()
            Button { showLyrics.toggle() } label: {
                Image(systemName: "quote.bubble")
                    .foregroundStyle(showLyrics ? Palette.accentCuivre : Palette.texteIvoire)
            }
            Spacer()
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet").foregroundStyle(Palette.texteIvoire)
            }
            #if os(iOS)
            Spacer()
            RoutePickerView()
                .frame(width: 32, height: 32)
            #endif
        }
        .font(.title3)
        .buttonStyle(.plain)
    }
}

#if os(iOS)
/// Sélecteur de sortie audio (AirPlay / Bluetooth) natif.
private struct RoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor(Palette.texteIvoire)
        view.activeTintColor = UIColor(Palette.accentCuivre)
        view.prioritizesVideoDevices = false
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
