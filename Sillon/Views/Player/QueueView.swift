import SwiftUI

/// Panneau réutilisable : bascule entre les TITRES DE L'ALBUM du morceau courant (par défaut) et la
/// FILE D'ATTENTE de lecture. Tap = saut (file) / lecture de l'album (album). Utilisé en feuille
/// (iPhone/portrait) et en colonne du lecteur paysage (iPad), façon Android.
struct QueuePanel: View {
    @Environment(\.playerController) private var player
    /// Appelé après un saut dans la file (ex. fermer la feuille en portrait) ; nil en colonne inline.
    var onJump: (() -> Void)? = nil

    private enum Mode: Hashable { case album, queue }
    @State private var mode: Mode = .album

    /// Titres de l'album du morceau courant, ordonnés (disque puis numéro de piste).
    private var albumTracks: [Track] {
        guard let album = player?.currentTrack?.album else { return [] }
        return album.tracks.onActiveServers().sorted {
            ($0.discNumber ?? 0, $0.trackNumber ?? 0, $0.title)
                < ($1.discNumber ?? 0, $1.trackNumber ?? 0, $1.title)
        }
    }

    /// La file d'attente est-elle IDENTIQUE à l'album en cours (mêmes titres, même ordre) ? Si oui, le
    /// segment « File d'attente » n'apporte rien → on le masque et on n'affiche que l'album (façon Android).
    private var sameAsAlbum: Bool {
        guard let player else { return false }
        let album = albumTracks.map(\.id)
        return !album.isEmpty && player.queue.map(\.id) == album
    }

    var body: some View {
        VStack(spacing: 0) {
            // Bascule visible seulement si la file DIFFÈRE de l'album en cours.
            if !sameAsAlbum {
                Picker("", selection: $mode) {
                    Text(LanguageManager.string("Album")).tag(Mode.album)
                    Text(LanguageManager.string("File d'attente")).tag(Mode.queue)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s)
            }

            Group {
                switch sameAsAlbum ? .album : mode {
                case .album: albumList
                case .queue: queueList
                }
            }
        }
        .onChange(of: sameAsAlbum) { _, same in if same { mode = .album } }
    }

    /// Titres de l'album du morceau courant (tap = lecture de l'album à partir du titre).
    @ViewBuilder private var albumList: some View {
        let tracks = albumTracks
        if let player, !tracks.isEmpty {
            List {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    row(track: track, isCurrent: track.id == player.currentTrack?.id)
                        .contentShape(Rectangle())
                        .onTapGesture { player.play(queue: tracks, startAt: index) }
                }
            }
            .listStyle(.plain)
        } else {
            ContentUnavailableView(LanguageManager.string("Aucun album"), systemImage: "square.stack")
        }
    }

    /// File d'attente de lecture (tap = saut).
    @ViewBuilder private var queueList: some View {
        if let player, !player.queue.isEmpty {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, track in
                    row(track: track, isCurrent: index == player.currentIndex)
                        .contentShape(Rectangle())
                        .onTapGesture { player.jump(to: index); onJump?() }
                }
            }
            .listStyle(.plain)
        } else {
            ContentUnavailableView(LanguageManager.string("File vide"), systemImage: "list.bullet")
        }
    }

    private func row(track: Track, isCurrent: Bool) -> some View {
        HStack(spacing: Spacing.m) {
            CoverArtView(path: track.album?.coverArtRemotePath,
                         server: track.server,
                         seed: track.album?.title ?? track.title)
                .frame(width: 44, height: 44)
                .overlay {
                    // Marqueur « en lecture » superposé à la pochette du morceau courant.
                    if isCurrent {
                        ZStack {
                            Color.black.opacity(0.45)
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption).foregroundStyle(.white)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCorner, style: .continuous))
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(Typo.corps).lineLimit(1)
                    .foregroundStyle(isCurrent ? Palette.accentCuivre : Palette.texteIvoire)
                Text(track.artistNameSnapshot ?? track.album?.artist?.name ?? "")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(track.durationSeconds.asTrackDuration)
                .font(Typo.technique).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

/// Feuille « file d'attente » (iPhone / portrait) : enveloppe [QueuePanel] dans un NavigationStack.
struct QueueView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QueuePanel(onJump: { dismiss() })
                .navigationTitle(LanguageManager.string("Lecture"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
                }
                .background(Palette.fondNoir)
        }
    }
}
