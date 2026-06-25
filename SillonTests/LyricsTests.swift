import Testing
import Foundation
@testable import Sillon

struct LyricsTests {

    // MARK: - Décodage Jellyfin (Start en ticks .NET 100 ns) — fixture réelle

    @Test func decodesJellyfinSyncedLyricsAndConvertsTicks() throws {
        let json = """
        { "Lyrics": [
            { "Text": "You never gonna get along", "Start": 128100000, "Cues": [] },
            { "Text": "You never gonna get it on", "Start": 218500000, "Cues": [] }
          ], "Metadata": {} }
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(JellyfinLyricsResponse.self, from: json)
        let lines = (r.Lyrics ?? []).map { LyricLine(timeSeconds: $0.Start.map { Double($0) / 10_000_000.0 }, text: $0.Text ?? "") }
        #expect(lines.count == 2)
        #expect(abs((lines[0].timeSeconds ?? 0) - 12.81) < 0.001)   // 128100000 ticks = 12.81 s
        #expect(abs((lines[1].timeSeconds ?? 0) - 21.85) < 0.001)
        #expect(lines.contains { $0.timeSeconds != nil })           // => synced
    }

    @Test func decodesJellyfinUnsyncedLyrics() throws {
        let json = """
        { "Lyrics": [ { "Text": "If it's love that you're running from" }, { "Text": "There is no hiding place" } ] }
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(JellyfinLyricsResponse.self, from: json)
        let lines = (r.Lyrics ?? []).map { LyricLine(timeSeconds: $0.Start.map { Double($0) / 10_000_000.0 }, text: $0.Text ?? "") }
        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0.timeSeconds == nil })
    }

    // MARK: - Décodage OpenSubsonic (start en ms, offset)

    @Test func decodesOpenSubsonicStructuredLyrics() throws {
        let json = """
        { "subsonic-response": { "status": "ok", "lyricsList": { "structuredLyrics": [
            { "synced": true, "lang": "eng", "offset": 0,
              "line": [ { "start": 12810, "value": "Première ligne" }, { "start": 21850, "value": "Deuxième" } ] }
          ] } } }
        """.data(using: .utf8)!
        let env = try JSONDecoder().decode(SubsonicResponseEnvelope.self, from: json)
        let s = try #require(env.subsonicResponse.lyricsList?.structuredLyrics?.first)
        #expect(s.synced == true)
        let lines = (s.line ?? []).map { LyricLine(timeSeconds: $0.start.map { Double($0) / 1000.0 }, text: $0.value ?? "") }
        #expect(abs((lines[0].timeSeconds ?? 0) - 12.81) < 0.001)   // 12810 ms = 12.81 s
        #expect(lines[1].text == "Deuxième")
    }

    @Test func decodesSubsonicWithoutLyricsAsNil() throws {
        let json = """
        { "subsonic-response": { "status": "ok" } }
        """.data(using: .utf8)!
        let env = try JSONDecoder().decode(SubsonicResponseEnvelope.self, from: json)
        #expect(env.subsonicResponse.lyricsList == nil)
    }

    // MARK: - Sélection de la ligne courante

    @Test func activeLineIndexFollowsPlayback() {
        let lyrics = TrackLyrics(synced: true, lines: [
            LyricLine(timeSeconds: 10, text: "A"),
            LyricLine(timeSeconds: 20, text: "B"),
            LyricLine(timeSeconds: 30, text: "C"),
        ])
        #expect(lyrics.activeLineIndex(at: 5) == nil)    // avant la 1re ligne
        #expect(lyrics.activeLineIndex(at: 10) == 0)     // pile sur la 1re
        #expect(lyrics.activeLineIndex(at: 19.9) == 0)
        #expect(lyrics.activeLineIndex(at: 20) == 1)
        #expect(lyrics.activeLineIndex(at: 999) == 2)    // après la dernière => reste la dernière
    }

    @Test func activeLineIndexRobustToUnsortedInput() {
        // Même si un serveur renvoyait des lignes non triées, on prend bien la ligne dont le temps
        // est le plus grand parmi ceux <= t (pas de saut à la mauvaise ligne).
        let lyrics = TrackLyrics(synced: true, lines: [
            LyricLine(timeSeconds: 5, text: "A"),
            LyricLine(timeSeconds: 30, text: "C"),
            LyricLine(timeSeconds: 15, text: "B"),
        ])
        #expect(lyrics.activeLineIndex(at: 20) == 2)   // t=15 (index 2) est le plus grand <= 20
        #expect(lyrics.activeLineIndex(at: 40) == 1)   // t=30 (index 1)
        #expect(lyrics.activeLineIndex(at: 3) == nil)
    }

    @Test func activeLineIndexSkipsUnsyncedLeadingLines() {
        // Une ligne non horodatée (titre/♪) en tête ne doit pas perturber la sélection.
        let lyrics = TrackLyrics(synced: true, lines: [
            LyricLine(timeSeconds: nil, text: "♪"),
            LyricLine(timeSeconds: 8, text: "A"),
            LyricLine(timeSeconds: 16, text: "B"),
        ])
        #expect(lyrics.activeLineIndex(at: 4) == nil)
        #expect(lyrics.activeLineIndex(at: 8) == 1)
        #expect(lyrics.activeLineIndex(at: 16) == 2)
    }
}
