import Foundation
import SwiftData

/// Données d'exemple pour les Previews SwiftUI — purement en mémoire, jamais utilisées en production.
/// Permet de prévisualiser les écrans Bibliothèque/Accueil sans serveur réel ni accès réseau.
enum PreviewData {
    @MainActor
    static func populate(_ context: ModelContext) {
        let server = ServerAccount(name: "Démo", type: .local, baseURLString: "", username: "demo")
        context.insert(server)
        let sid = server.id

        let catalogue: [(artist: String, albums: [(title: String, year: Int, tracks: [String])])] = [
            ("Miles Davis", [
                ("Kind of Blue", 1959, ["So What", "Freddie Freeloader", "Blue in Green"]),
                ("Bitches Brew", 1970, ["Pharaoh's Dance", "Bitches Brew"])
            ]),
            ("Radiohead", [
                ("OK Computer", 1997, ["Airbag", "Paranoid Android", "Karma Police"]),
                ("In Rainbows", 2007, ["15 Step", "Bodysnatchers", "Nude"])
            ]),
            ("Daft Punk", [
                ("Random Access Memories", 2013, ["Give Life Back to Music", "Get Lucky", "Instant Crush"])
            ])
        ]

        var added = Date(timeIntervalSinceNow: -86_400 * 30)
        for (artistIndex, entry) in catalogue.enumerated() {
            let artist = Artist(serverID: sid, remoteID: "ar\(artistIndex)", name: entry.artist)
            artist.server = server
            context.insert(artist)

            for (albumIndex, albumEntry) in entry.albums.enumerated() {
                added.addTimeInterval(86_400 * 3)
                let album = Album(serverID: sid, remoteID: "al\(artistIndex)_\(albumIndex)", title: albumEntry.title)
                album.year = albumEntry.year
                album.artist = artist
                album.artistNameSnapshot = entry.artist
                album.server = server
                album.dateAdded = added
                album.isFavorite = (artistIndex + albumIndex) % 3 == 0
                album.favoriteDate = album.isFavorite ? added : nil
                context.insert(album)

                for (trackIndex, title) in albumEntry.tracks.enumerated() {
                    let track = Track(serverID: sid, remoteID: "tr\(artistIndex)_\(albumIndex)_\(trackIndex)", title: title, durationSeconds: Double(180 + trackIndex * 37))
                    track.trackNumber = trackIndex + 1
                    track.format = trackIndex.isMultiple(of: 2) ? "flac" : "mp3"
                    track.bitrate = trackIndex.isMultiple(of: 2) ? 1024 : 320
                    track.artistNameSnapshot = entry.artist
                    track.album = album
                    track.server = server
                    track.dateAdded = added
                    context.insert(track)
                }
            }
        }
    }
}
