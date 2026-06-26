import SwiftUI

/// Carte de piste (pochette de l'album + titre + artiste), pour les carrousels de morceaux de l'accueil
/// (ex. « Pistes préférées »). Même gabarit visuel qu'`AlbumCard` ; le tap est géré par l'appelant.
struct TrackCard: View {
    let track: Track
    var size: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            CoverArtView(
                path: track.album?.coverArtRemotePath,
                server: track.server,
                seed: track.album?.title ?? track.title,
                preferredSize: Int(size * 2),
                showsSource: true
            )
            .frame(width: size, height: size)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline)
                    .foregroundStyle(Palette.texteIvoire)
                    .lineLimit(1)
                if let artist = track.artistNameSnapshot ?? track.album?.artist?.name {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: size, alignment: .leading)
        }
    }
}
