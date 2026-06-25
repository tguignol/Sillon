import SwiftUI
import SwiftData

/// Feuille d'ajout de morceaux à une playlist : choisir une playlist existante ou en créer une.
struct AddToPlaylistView: View {
    let tracks: [Track]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Playlist.updatedAt, order: .reverse) private var playlists: [Playlist]
    @State private var newName = ""
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if isCreating {
                        HStack {
                            TextField("Nom de la playlist", text: $newName)
                            Button("Créer") {
                                let playlist = PlaylistActions.create(name: newName, context: context)
                                PlaylistActions.add(tracks, to: playlist, context: context)
                                dismiss()
                            }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else {
                        Button { isCreating = true } label: {
                            Label("Nouvelle playlist", systemImage: "plus")
                        }
                    }
                }

                Section("Mes playlists") {
                    if playlists.isEmpty {
                        Text("Aucune playlist pour l'instant").foregroundStyle(.secondary)
                    } else {
                        ForEach(playlists) { playlist in
                            Button {
                                PlaylistActions.add(tracks, to: playlist, context: context)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(playlist.name).foregroundStyle(Palette.texteIvoire)
                                    Spacer()
                                    Text("\(playlist.items.count)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(tracks.count == 1 ? "Ajouter à…" : "Ajouter \(tracks.count) titres")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            }
        }
    }
}
