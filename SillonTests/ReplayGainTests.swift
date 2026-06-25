import Testing
import Foundation
@testable import Sillon

struct ReplayGainTests {

    // Tolérance pour les comparaisons de facteurs linéaires.
    private func approx(_ a: Float, _ b: Float, eps: Float = 0.001) -> Bool { abs(a - b) < eps }

    @Test func offModeIsAlwaysNeutral() {
        let f = ReplayGain.linearFactor(
            mode: .off,
            trackGain: -6, trackPeak: 0.9, albumGain: -8, albumPeak: 0.95,
            fallbackGain: -5, preampDB: 3, clipProtection: true)
        #expect(f == 1.0)
    }

    @Test func trackModeConvertsDecibelsToLinear() {
        // -6 dB ≈ 0.5012 ; +6 dB ≈ 1.9953. Pas de peak => pas de réduction (sans clip protection).
        let down = ReplayGain.linearFactor(
            mode: .track, trackGain: -6, trackPeak: nil, albumGain: nil, albumPeak: nil,
            fallbackGain: nil, preampDB: 0, clipProtection: false)
        #expect(approx(down, 0.5012))
        let up = ReplayGain.linearFactor(
            mode: .track, trackGain: 6, trackPeak: nil, albumGain: nil, albumPeak: nil,
            fallbackGain: nil, preampDB: 0, clipProtection: false)
        #expect(approx(up, 1.9953))
    }

    @Test func albumModePrefersAlbumGainOverTrackGain() {
        let f = ReplayGain.linearFactor(
            mode: .album, trackGain: -3, trackPeak: nil, albumGain: -9, albumPeak: nil,
            fallbackGain: nil, preampDB: 0, clipProtection: false)
        #expect(approx(f, pow(10, -9.0 / 20.0)))
    }

    @Test func albumModeFallsBackToAlbumRelationThenTrackThenFallback() {
        // albumGain (par-song) absent => relation Album.
        let viaRelation = ReplayGain.linearFactor(
            mode: .album, trackGain: -3, trackPeak: nil, albumGain: nil, albumPeak: nil,
            albumRelGain: -9, albumRelPeak: nil, fallbackGain: nil, preampDB: 0, clipProtection: false)
        #expect(approx(viaRelation, pow(10, -9.0 / 20.0)))

        // album + relation absents => trackGain.
        let viaTrack = ReplayGain.linearFactor(
            mode: .album, trackGain: -3, trackPeak: nil, albumGain: nil, albumPeak: nil,
            albumRelGain: nil, albumRelPeak: nil, fallbackGain: -12, preampDB: 0, clipProtection: false)
        #expect(approx(viaTrack, pow(10, -3.0 / 20.0)))

        // tout absent sauf fallback => fallbackGain.
        let viaFallback = ReplayGain.linearFactor(
            mode: .album, trackGain: nil, trackPeak: nil, albumGain: nil, albumPeak: nil,
            albumRelGain: nil, albumRelPeak: nil, fallbackGain: -12, preampDB: 0, clipProtection: false)
        #expect(approx(viaFallback, pow(10, -12.0 / 20.0)))
    }

    @Test func noGainDataIsNeutral() {
        let f = ReplayGain.linearFactor(
            mode: .track, trackGain: nil, trackPeak: nil, albumGain: nil, albumPeak: nil,
            fallbackGain: nil, preampDB: 0, clipProtection: true)
        #expect(f == 1.0)
    }

    @Test func clipProtectionCapsByKnownPeak() {
        // +6 dB (≈1.995) avec peak 0.8 => plafond 1/0.8 = 1.25.
        let f = ReplayGain.linearFactor(
            mode: .track, trackGain: 6, trackPeak: 0.8, albumGain: nil, albumPeak: nil,
            fallbackGain: nil, preampDB: 0, clipProtection: true)
        #expect(approx(f, 1.25))
    }

    @Test func clipProtectionWithoutPeakNeverAmplifies() {
        // +6 dB sans peak (cas Jellyfin) => borné à 1.0.
        let f = ReplayGain.linearFactor(
            mode: .track, trackGain: 6, trackPeak: nil, albumGain: nil, albumPeak: nil,
            fallbackGain: nil, preampDB: 0, clipProtection: true)
        #expect(f == 1.0)
    }

    @Test func clipProtectionLeavesQuietGainUntouched() {
        // -6 dB (≈0.501) avec peak 0.9 : 0.501*0.9 < 1 => pas de réduction.
        let f = ReplayGain.linearFactor(
            mode: .track, trackGain: -6, trackPeak: 0.9, albumGain: nil, albumPeak: nil,
            fallbackGain: nil, preampDB: 0, clipProtection: true)
        #expect(approx(f, 0.5012))
    }

    @Test func preampAddsDecibels() {
        // -6 dB + 6 dB de pré-ampli = 0 dB => 1.0 (sans clip pour isoler le pré-ampli).
        let f = ReplayGain.linearFactor(
            mode: .track, trackGain: -6, trackPeak: nil, albumGain: nil, albumPeak: nil,
            fallbackGain: nil, preampDB: 6, clipProtection: false)
        #expect(approx(f, 1.0))
    }

    // MARK: - Décodage OpenSubsonic

    @Test func decodesOpenSubsonicReplayGainObject() throws {
        let json = """
        { "id": "1", "title": "T", "duration": 200,
          "replayGain": { "trackGain": -7.2, "albumGain": -8.1, "trackPeak": 0.98,
                          "albumPeak": 1.02, "baseGain": 0, "fallbackGain": -6 } }
        """.data(using: .utf8)!
        let song = try JSONDecoder().decode(SubsonicSong.self, from: json)
        #expect(song.replayGain?.trackGain == -7.2)
        #expect(song.replayGain?.albumGain == -8.1)
        #expect(song.replayGain?.trackPeak == 0.98)
        #expect(song.replayGain?.albumPeak == 1.02)
        #expect(song.replayGain?.fallbackGain == -6)
    }

    @Test func decodesSongWithoutReplayGainAsNil() throws {
        // Subsonic legacy : pas d'objet replayGain => nil, sans casser le décodage.
        let json = """
        { "id": "1", "title": "T", "duration": 200 }
        """.data(using: .utf8)!
        let song = try JSONDecoder().decode(SubsonicSong.self, from: json)
        #expect(song.replayGain == nil)
    }
}
