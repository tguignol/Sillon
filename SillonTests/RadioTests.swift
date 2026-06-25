import Testing
import Foundation
@testable import Sillon

struct RadioTests {

    @Test func decodesSubsonicSongGenre() throws {
        let json = """
        { "subsonic-response": { "status": "ok",
          "song": { "id": "s1", "title": "Saturday Rocks", "artist": "Liquido", "genre": "Alternative" } } }
        """.data(using: .utf8)!
        let env = try JSONDecoder().decode(SubsonicResponseEnvelope.self, from: json)
        #expect(env.subsonicResponse.song?.genre == "Alternative")
    }

    @Test func decodesSubsonicSongsByGenre() throws {
        let json = """
        { "subsonic-response": { "status": "ok", "songsByGenre": { "song": [
            { "id": "a", "title": "All the Way", "artist": "Ramones" },
            { "id": "b", "title": "Danny Says", "artist": "Ramones" }
          ] } } }
        """.data(using: .utf8)!
        let env = try JSONDecoder().decode(SubsonicResponseEnvelope.self, from: json)
        let songs = try #require(env.subsonicResponse.songsByGenre?.song)
        #expect(songs.count == 2)
        #expect(songs.first?.title == "All the Way")
    }

    @Test func decodesJellyfinInstantMixAsItems() throws {
        // InstantMix renvoie la forme standard { Items: [...], TotalRecordCount }.
        let json = """
        { "Items": [
            { "Id": "i1", "Name": "Mind Riot", "RunTimeTicks": 1500000000 },
            { "Id": "i2", "Name": "Downfall" }
          ], "TotalRecordCount": 201 }
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(JellyfinItemsResponse.self, from: json)
        #expect(r.Items.count == 2)
        #expect(r.TotalRecordCount == 201)
        #expect(r.Items.first?.Name == "Mind Riot")
    }
}
