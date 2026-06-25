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
}
