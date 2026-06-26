import SwiftUI
import SwiftData

/// Détail d'une playlist : lecture, réordonnancement par glisser-déposer (`onMove`), suppression
/// d'éléments (`onDelete`).
struct PlaylistDetailView: View {
    let playlist: Playlist
    @Environment(\.modelContext) private var context
    @Environment(\.playerController) private var player

    // Une playlist peut mélanger des pistes de plusieurs serveurs : on masque celles d'un serveur
    // désactivé (affichage + lecture). Cas commun (mono-serveur / tous actifs) : aucun changement.
    private var orderedItems: [PlaylistItem] {
        playlist.items
            .filter { item in
                guard let track = item.track else { return false }   // exclut les items sans piste
                return track.server?.isActive ?? true
            }
            .sorted { $0.position < $1.position }
    }
    private var orderedTracks: [Track] { orderedItems.compactMap(\.track) }

    var body: some View {
        Group {
            if orderedItems.isEmpty {
                ContentUnavailableView(
                    "Playlist vide",
                    systemImage: "music.note.list",
                    description: Text("Ajoutez des titres depuis la bibliothèque (appui long sur un titre ▸ Ajouter à une playlist).")
                )
            } else {
                List {
                    ForEach(Array(orderedItems.enumerated()), id: \.element.id) { index, item in
                        if let track = item.track {
                            TrackRowView(track: track, showsTrackNumber: false, showsArtwork: true)
                                .contentShape(Rectangle())
                                .onTapGesture { player?.play(queue: orderedTracks, startAt: index) }
                                .trackContextMenu(track: track, context: context)
                        }
                    }
                    .onDelete { offsets in
                        PlaylistActions.removeItems(at: offsets, from: orderedItems, playlist: playlist, context: context)
                    }
                    .onMove { source, destination in
                        PlaylistActions.move(orderedItems, from: source, to: destination, playlist: playlist, context: context)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(playlist.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !orderedTracks.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button { player?.play(queue: orderedTracks, startAt: 0) } label: {
                        Label("Lire", systemImage: "play.fill")
                    }
                }
            }
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            #endif
        }
    }
}
