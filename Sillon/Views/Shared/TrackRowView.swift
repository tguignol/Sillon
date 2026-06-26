import SwiftUI

/// Ligne de morceau réutilisée par la liste Titres, le détail d'album et (à terme) les playlists.
///
/// La lecture réelle arrive au commit "Lecteur + Égaliseur" : ici la ligne est informative
/// (numéro de piste, titre, badge technique, durée, état de téléchargement).
struct TrackRowView: View {
    let track: Track
    /// Affiche le numéro de piste à gauche (vrai dans un album), sinon l'artiste (vrai dans une
    /// liste hétérogène comme "Titres").
    var showsTrackNumber: Bool = true
    /// Affiche un bouton « ⋮ » à droite de la durée ouvrant le menu d'actions (façon Symfonium).
    var showsMenu: Bool = false
    /// Affiche la pochette de l'album à gauche (icône du morceau) au lieu du n° de piste / symbole —
    /// utilisé par la liste « Titres » où chaque ligne provient d'un album différent.
    var showsArtwork: Bool = false

    var body: some View {
        HStack(spacing: Spacing.m) {
            leading

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(Typo.corps)
                    .lineLimit(1)
                if !showsTrackNumber, let artist = track.artistNameSnapshot ?? track.album?.artist?.name {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !track.technicalBadge.isEmpty {
                    Text(track.technicalBadge)
                        .font(Typo.technique)
                        .foregroundStyle(Palette.signalTeal)
                        .lineLimit(1)
                }
            }

            Spacer()

            if track.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.accentCuivre)
            }
            DownloadButton(track: track)
            Text(track.durationSeconds.asTrackDuration)
                .font(Typo.technique)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if showsMenu {
                TrackMenuButton(track: track)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var leading: some View {
        if showsArtwork {
            CoverArtView(path: track.album?.coverArtRemotePath,
                         server: track.server,
                         seed: track.album?.title ?? track.title)
                .frame(width: 44, height: 44)
        } else if showsTrackNumber, let number = track.trackNumber {
            Text("\(number)")
                .font(Typo.technique)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .center)
        } else {
            Image(systemName: "music.note")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .center)
        }
    }
}
