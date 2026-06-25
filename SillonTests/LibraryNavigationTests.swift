import Testing
import Foundation
@testable import Sillon

struct LibraryNavigationTests {

    @Test func jellyfinDecodesGenres() throws {
        let json = """
        { "Id": "i1", "Name": "Song", "Genres": ["Rock", "Alternative"] }
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(JellyfinBaseItem.self, from: json)
        #expect(item.Genres?.first == "Rock")
    }

    @Test func subsonicDecodesGenre() throws {
        let json = """
        { "id": "s1", "title": "T", "genre": "Jazz" }
        """.data(using: .utf8)!
        let song = try JSONDecoder().decode(SubsonicSong.self, from: json)
        #expect(song.genre == "Jazz")
    }

    @Test func albumSortOrdersHaveDescriptors() {
        for order in AlbumSortOrder.allCases {
            #expect(!order.descriptors.isEmpty)
            #expect(!order.label.isEmpty)
        }
    }

    @Test func parsesSubsonicDatesIncludingNanoseconds() {
        // Navidrome renvoie des nanosecondes (9 décimales) — rejetées par l'ISO8601 standard.
        #expect(SubsonicProvider.parseDate("2026-06-24T12:28:00.382717832Z") != nil)
        #expect(SubsonicProvider.parseDate("2026-06-24T12:28:00.382Z") != nil)   // millisecondes
        #expect(SubsonicProvider.parseDate("2026-06-24T12:28:00Z") != nil)        // sans fraction
        #expect(SubsonicProvider.parseDate(nil) == nil)
        #expect(SubsonicProvider.parseDate("") == nil)
        // Cohérence : la date nanoseconde tombe bien à la bonne seconde.
        let d = SubsonicProvider.parseDate("2026-06-24T12:28:00.382717832Z")!
        let plain = SubsonicProvider.parseDate("2026-06-24T12:28:00Z")!
        #expect(abs(d.timeIntervalSince(plain) - 0.382) < 0.01)
    }
}
