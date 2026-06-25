import SwiftUI
import SwiftData

/// Liste à plat de tous les morceaux, triés par titre. La ligne affiche l'artiste plutôt que le
/// numéro de piste (liste hétérogène, contrairement au détail d'album).
struct TracksListView: View {
    @Query(sort: \Track.title) private var tracks: [Track]

    var body: some View {
        if tracks.isEmpty {
            LibraryEmptyState(title: "Aucun titre", systemImage: "music.note")
        } else {
            List(tracks) { track in
                TrackRowView(track: track, showsTrackNumber: false)
            }
            .listStyle(.plain)
        }
    }
}

#Preview {
    let container = SillonSchema.makeContainer(inMemory: true)
    PreviewData.populate(container.mainContext)
    return NavigationStack { TracksListView() }
        .modelContainer(container)
}
