import SwiftUI
import SwiftData

/// Menu contextuel réutilisable sur une ligne de morceau : bascule favori + ajout à une playlist.
/// Permet le « toggle cœur partout » et l'ajout aux playlists sans alourdir chaque ligne.
private struct TrackContextMenu: ViewModifier {
    let track: Track
    let context: ModelContext
    @State private var showAddToPlaylist = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    Favorites.toggle(track, context: context)
                } label: {
                    Label(track.isFavorite ? "Retirer des favoris" : "Ajouter aux favoris",
                          systemImage: track.isFavorite ? "heart.slash" : "heart")
                }
                Button {
                    showAddToPlaylist = true
                } label: {
                    Label("Ajouter à une playlist", systemImage: "text.badge.plus")
                }
            }
            .sheet(isPresented: $showAddToPlaylist) {
                AddToPlaylistView(tracks: [track])
            }
    }
}

extension View {
    func trackContextMenu(track: Track, context: ModelContext) -> some View {
        modifier(TrackContextMenu(track: track, context: context))
    }
}
