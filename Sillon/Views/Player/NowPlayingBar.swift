import SwiftUI

/// Contenu du mini-lecteur. Présenté via `tabViewBottomAccessory` sur iOS 26 (slot natif au-dessus
/// de la barre d'onglets) et via `safeAreaInset` sur macOS — le conteneur fournit le fond, ce contenu
/// reste sobre. Tapé, il ouvre le lecteur plein écran.
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
                .frame(width: 36, height: 36)

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

                Spacer(minLength: Spacing.s)

                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(Palette.texteIvoire)
                        .contentShape(Rectangle())
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.m)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
        }
    }
}
