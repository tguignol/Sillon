import SwiftUI

/// Mini-lecteur ancré au-dessus de la barre d'onglets quand un morceau est en cours. Tapé, il
/// ouvre l'écran lecteur plein écran.
struct NowPlayingBar: View {
    @Environment(\.playerController) private var player
    var onTap: () -> Void

    var body: some View {
        if let player, let track = player.currentTrack {
            HStack(spacing: Spacing.m) {
                CoverArtView(
                    path: track.album?.coverArtRemotePath,
                    server: track.server,
                    seed: track.album?.title ?? track.title,
                    preferredSize: 96
                )
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.subheadline)
                        .foregroundStyle(Palette.texteIvoire)
                        .lineLimit(1)
                    Text(track.artistNameSnapshot ?? track.album?.artist?.name ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(Palette.texteIvoire)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .background(Palette.surfaceElevee, in: RoundedRectangle(cornerRadius: Spacing.cardCorner, style: .continuous))
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Palette.accentCuivre)
                        .frame(width: geo.size.width * progress(player))
                        .frame(maxHeight: 2, alignment: .bottom)
                }
                .frame(height: 2)
            }
            .padding(.horizontal, Spacing.m)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
        }
    }

    private func progress(_ player: PlayerController) -> Double {
        player.duration > 0 ? min(1, player.currentTime / player.duration) : 0
    }
}
