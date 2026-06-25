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
                artwork(track: track, player: player)
                titles(track: track)
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
            .sheet(isPresented: $showEQ) { EQView() }
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
            Button { showEQ = true } label: {
                Image(systemName: "slider.vertical.3").font(.title3).foregroundStyle(Palette.signalTeal)
            }
        }
        .buttonStyle(.plain)
    }

    private func artwork(track: Track, player: PlayerController) -> some View {
        ZStack {
            SpectrumRingView(levels: player.spectrum, waveform: player.waveform, style: spectrumStyle)
            CoverArtView(path: track.album?.coverArtRemotePath, server: track.server, seed: track.album?.title ?? track.title, preferredSize: 600)
                .clipShape(Circle())
                .padding(26)
        }
        .frame(maxWidth: 320)
        .aspectRatio(1, contentMode: .fit)
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
            if !track.technicalBadge.isEmpty {
                Text(track.technicalBadge)
                    .font(Typo.technique)
                    .foregroundStyle(Palette.signalTeal)
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
        HStack {
            Button { player.toggleFavoriteOfCurrent() } label: {
                Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(track.isFavorite ? Palette.accentCuivre : Palette.texteIvoire)
            }
            .buttonStyle(.plain)
            Spacer()
            #if os(iOS)
            RoutePickerView()
                .frame(width: 40, height: 40)
            #endif
        }
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
