import SwiftUI

/// Panneau du lecteur : bascule entre les TITRES DE L'ALBUM du morceau courant (par défaut) et la
/// FILE D'ATTENTE de lecture. File : morceau en cours mis en évidence, saut direct (tap) et
/// réordonnancement par glisser-déposer. Album : titres de l'album en ordre de piste (tap = lecture).
struct QueueView: View {
    @Environment(\.playerController) private var player
    @Environment(\.dismiss) private var dismiss

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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    Text(LanguageManager.string("Album")).tag(Mode.album)
                    Text(LanguageManager.string("File d'attente")).tag(Mode.queue)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.s)

                Group {
                    switch mode {
                    case .album: albumList
                    case .queue: queueList
                    }
                }
            }
            .navigationTitle(LanguageManager.string(mode == .album ? "Album" : "File d'attente"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
                #if os(iOS)
                if mode == .queue {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
                #endif
            }
            .background(Palette.fondNoir)
        }
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

    /// File d'attente de lecture (saut direct + réordonnancement).
    @ViewBuilder private var queueList: some View {
        if let player, !player.queue.isEmpty {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, track in
                    row(track: track, isCurrent: index == player.currentIndex)
                        .contentShape(Rectangle())
                        .onTapGesture { player.jump(to: index); dismiss() }
                }
                .onMove { source, destination in player.moveQueue(from: source, to: destination) }
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
