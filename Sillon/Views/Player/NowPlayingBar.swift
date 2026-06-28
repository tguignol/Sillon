import SwiftUI

/// Mini-lecteur (façon Android). ADAPTATIF :
/// - **large** (iPad paysage / Mac) : pochette + cœur + titre/artiste·album + barre de progression fine
///   (draggable) avec temps écoulé/restant + précédent / lecture / suivant.
/// - **étroit** (iPhone / portrait) : pochette + titre/artiste + suivant + lecture.
/// Tapé (hors boutons), il ouvre le lecteur plein écran.
struct NowPlayingBar: View {
    @Environment(\.playerController) private var player
    var onTap: () -> Void

    var body: some View {
        if let player, let track = player.currentTrack {
            richBar(player: player, track: track)
                .contentShape(Rectangle())
                .onTapGesture { onTap() }
        }
    }

    private func richBar(player: PlayerController, track: Track) -> some View {
        HStack(spacing: Spacing.m) {
            cover(track, size: 48)

            Button { player.toggleFavoriteOfCurrent() } label: {
                Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(track.isFavorite ? Palette.accentCuivre : Palette.texteIvoire)
            }
            .buttonStyle(.plain)

            VStack(spacing: 2) {
                Text(track.title)
                    .font(.subheadline).foregroundStyle(Palette.texteIvoire).lineLimit(1)
                Text(subtitle(track))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: Spacing.s) {
                    Text(player.currentTime.asTrackDuration)
                        .font(Typo.technique).foregroundStyle(.secondary).monospacedDigit()
                    MiniScrubber(current: player.currentTime, duration: player.duration) { player.seek(to: $0) }
                    Text("-" + max(player.duration - player.currentTime, 0).asTrackDuration)
                        .font(Typo.technique).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity)

            Button { player.previous() } label: {
                Image(systemName: "backward.end.fill").foregroundStyle(Palette.texteIvoire)
            }
            .buttonStyle(.plain)
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 38)).foregroundStyle(Palette.texteIvoire)
            }
            .buttonStyle(.plain)
            Button { player.next() } label: {
                Image(systemName: "forward.end.fill").foregroundStyle(Palette.texteIvoire)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.s)
    }

    private func cover(_ track: Track, size: CGFloat) -> some View {
        CoverArtView(
            path: track.album?.coverArtRemotePath,
            server: track.server,
            seed: track.album?.title ?? track.title,
            preferredSize: 96
        )
        .frame(width: size, height: size)
    }

    private func subtitle(_ track: Track) -> String {
        let artist = track.artistNameSnapshot ?? track.album?.artist?.name ?? ""
        let album = track.album?.title ?? ""
        return [artist, album].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Barre de progression FINE et draggable (façon Android) pour le mini-lecteur.
private struct MiniScrubber: View {
    let current: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void
    @State private var dragValue: TimeInterval?

    var body: some View {
        GeometryReader { geo in
            let value = dragValue ?? current
            let frac = duration > 0 ? min(max(value / duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.3)).frame(height: 3)
                Capsule().fill(Palette.accentCuivre).frame(width: geo.size.width * frac, height: 3)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in dragValue = min(max(g.location.x / geo.size.width, 0), 1) * duration }
                    .onEnded { _ in if let d = dragValue { onSeek(d); dragValue = nil } }
            )
        }
        .frame(height: 14)
    }
}
