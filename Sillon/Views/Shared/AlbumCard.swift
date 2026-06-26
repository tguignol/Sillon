import SwiftUI

/// Carte d'album (pochette + titre + artiste), réutilisée par la grille Albums, le détail d'artiste
/// et les sections de l'écran d'accueil. La taille est paramétrable pour permettre les formats
/// inégaux voulus par le système de design (grand format pour les ajouts récents, réduit ailleurs).
struct AlbumCard: View {
    let album: Album
    var size: CGFloat = 150
    /// Nombre de serveurs où cet album existe (dédup) : > 1 ⇒ pastille « N sources ».
    var sourceCount: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            CoverArtView(
                path: album.coverArtRemotePath,
                server: album.server,
                seed: album.title,
                preferredSize: Int(size * 2),
                showsSource: true,
                sourceCount: sourceCount
            )
            .frame(width: size, height: size)

            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.subheadline)
                    .foregroundStyle(Palette.texteIvoire)
                    .lineLimit(1)
                if let artist = album.artistNameSnapshot ?? album.artist?.name {
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
