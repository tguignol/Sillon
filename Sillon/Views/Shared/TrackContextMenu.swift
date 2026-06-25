import SwiftUI
import SwiftData

/// Actions d'un morceau (radio, favori, ajout à une playlist), partagées par le menu contextuel
/// (appui long) ET le bouton « ⋮ » inline façon Symfonium — une seule source de vérité.
struct TrackMenuContent: View {
    let track: Track
    let context: ModelContext
    @Binding var showAddToPlaylist: Bool
    @Environment(\.playerController) private var player

    var body: some View {
        Button {
            player?.startRadio(from: track)
        } label: {
            Label("Lancer une radio", systemImage: "antenna.radiowaves.left.and.right")
        }
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
}

/// Menu contextuel réutilisable sur une ligne de morceau (appui long).
private struct TrackContextMenu: ViewModifier {
    let track: Track
    let context: ModelContext
    @State private var showAddToPlaylist = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                TrackMenuContent(track: track, context: context, showAddToPlaylist: $showAddToPlaylist)
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

/// Bouton « ⋮ » (trois points verticaux) ouvrant le menu d'actions du morceau, façon Symfonium.
/// Placé à droite de la durée dans `TrackRowView` ; auto-suffisant (gère sa propre feuille playlist).
struct TrackMenuButton: View {
    let track: Track
    @Environment(\.modelContext) private var context
    @State private var showAddToPlaylist = false

    var body: some View {
        Menu {
            TrackMenuContent(track: track, context: context, showAddToPlaylist: $showAddToPlaylist)
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))   // points empilés verticalement (kebab)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 36)   // cible tactile confortable
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistView(tracks: [track])
        }
    }
}
