import SwiftUI
#if os(iOS)
import AVKit
#endif

/// Écran lecteur plein écran : pochette entourée du *groove ring*, métadonnées, barre de progression
/// avec -10s/+10s, transport, cœur favori et sélecteur de sortie audio (AirPlay).
struct PlayerView: View {
    @Environment(\.playerController) private var player
    @Environment(\.dismiss) private var dismiss
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
            VStack(spacing: Spacing.xl) {
                topBar
                Spacer(minLength: 0)
                // Les paroles remplacent la pochette/​spectre (à la Apple Music) : le transport reste
                // accessible dessous, sans fermer les paroles.
                if showLyrics {
                    LyricsView(track: track)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else {
                    artwork(track: track, player: player)
                }
                titles(track: track, format: player.currentFormatDescription, output: player.audioOutput)
                progressSection(player: player)
                transport(player: player)
                volumeSection(player: player)
                bottomRow(track: track, player: player)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.fondNoir)
            .animation(.easeInOut(duration: 0.25), value: showLyrics)
            .sheet(isPresented: $showEQ) { EQView() }
            .sheet(isPresented: $showQueue) { QueueView() }
        } else {
            ContentUnavailableView("Rien en lecture", systemImage: "music.note")
                .background(Palette.fondNoir)
        }
    }

    private var topBar: some View {
        HStack(spacing: Spacing.l) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.title3).foregroundStyle(Palette.texteIvoire)
            }
            Spacer()
            Menu {
                Picker("Visualisation", selection: $spectrumStyleRaw) {
                    ForEach(SpectrumStyle.allCases) { style in
                        Label(style.label, systemImage: style.systemImage).tag(style.rawValue)
                    }
                }
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

    private func artwork(track: Track, player: PlayerController) -> some View {
        ZStack {
            SpectrumRingView(levels: player.spectrum, waveform: player.waveform, style: spectrumStyle)
            CoverArtView(path: track.album?.coverArtRemotePath, server: track.server, seed: track.album?.title ?? track.title, preferredSize: 600)
                .clipShape(Circle())
                .padding(38)
        }
        .frame(maxWidth: 344)
        .aspectRatio(1, contentMode: .fit)
    }

    private func titles(track: Track, format: String?, output: AudioOutput?) -> some View {
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
            // Format réellement lu (codec · fréquence · profondeur · débit), sinon le badge du titre.
            let badge = (format?.isEmpty == false) ? format! : track.technicalBadge
            if !badge.isEmpty {
                Text(badge)
                    .font(Typo.technique)
                    .foregroundStyle(Palette.signalTeal)
            }
            // Sortie audio : transport + appareil (+ codec Bluetooth sur Android — non exposé par iOS).
            if let output {
                Label(output.summary, systemImage: output.transport.systemImage)
                    .font(Typo.technique)
                    .foregroundStyle(.secondary)
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
        HStack(spacing: Spacing.l) {
            Button { player.toggleFavoriteOfCurrent() } label: {
                Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(track.isFavorite ? Palette.accentCuivre : Palette.texteIvoire)
            }
            Spacer()
            Button { player.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(player.isShuffled ? Palette.accentCuivre : Palette.texteIvoire)
            }
            Button { player.cycleRepeatMode() } label: {
                Image(systemName: player.repeatMode.systemImage)
                    .foregroundStyle(player.repeatMode.isActive ? Palette.accentCuivre : Palette.texteIvoire)
            }
            Button { showLyrics.toggle() } label: {
                Image(systemName: "quote.bubble")
                    .foregroundStyle(showLyrics ? Palette.accentCuivre : Palette.texteIvoire)
            }
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet").foregroundStyle(Palette.texteIvoire)
            }
            #if os(iOS)
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
