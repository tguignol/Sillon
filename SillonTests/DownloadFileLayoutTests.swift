import Testing
import Foundation
import SwiftData
@testable import Sillon

@MainActor
struct DownloadFileLayoutTests {

    @Test func sanitizeRemovesPathSeparatorsAndInvalidChars() {
        let cleaned = DownloadFileLayout.sanitize("AC/DC: Live?*\"<>|")
        #expect(!cleaned.contains("/"))
        #expect(!cleaned.contains(":"))
        #expect(!cleaned.contains("?"))
        #expect(!cleaned.isEmpty)
    }

    @Test func sanitizeFallsBackForEmpty() {
        #expect(DownloadFileLayout.sanitize("") == "_")
        #expect(DownloadFileLayout.sanitize("   ") == "_")
    }

    @Test func destinationMirrorsServerTree() {
        let context = ModelContext(SillonSchema.makeContainer(inMemory: true))
        let server = ServerAccount(name: "Navidrome maison", type: .subsonic)
        context.insert(server)
        let artist = Artist(serverID: server.id, remoteID: "a", name: "Jeanne Mas")
        artist.server = server
        context.insert(artist)
        let album = Album(serverID: server.id, remoteID: "al", title: "Les Crises de l'âme")
        album.artist = artist
        album.server = server
        context.insert(album)
        let track = Track(serverID: server.id, remoteID: "t", title: "Tango", durationSeconds: 298)
        track.trackNumber = 3
        track.format = "m4a"
        track.album = album
        track.server = server
        context.insert(track)

        let dest = DownloadFileLayout.destination(for: track)
        let components = dest.pathComponents

        #expect(components.contains("Navidrome maison"))
        #expect(components.contains("Jeanne Mas"))
        #expect(components.contains("Les Crises de l'âme"))
        #expect(dest.lastPathComponent == "03 - Tango.m4a")
    }

    @Test func destinationUsesFallbackExtensionWhenFormatMissing() {
        let context = ModelContext(SillonSchema.makeContainer(inMemory: true))
        let server = ServerAccount(name: "S", type: .jellyfin)
        context.insert(server)
        let track = Track(serverID: server.id, remoteID: "t", title: "Sans format", durationSeconds: 1)
        track.server = server
        context.insert(track)

        #expect(DownloadFileLayout.destination(for: track).pathExtension == "audio")
    }
}
