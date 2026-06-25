import Testing
import Foundation
import AVFoundation
@testable import Sillon

struct EQBandsTests {

    @Test func frequenciesAreLogSpacedWithinRange() {
        let freqs = EQBands.frequencies(count: 8)
        #expect(freqs.count == 8)
        #expect(freqs.first! >= 30 && freqs.first! <= 35)      // ~32 Hz
        #expect(freqs.last! >= 15_000 && freqs.last! <= 16_500) // ~16 kHz
        // Strictement croissant.
        #expect(zip(freqs, freqs.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func labelFormatsKilohertz() {
        #expect(EQBands.label(for: 60) == "60")
        #expect(EQBands.label(for: 1000) == "1k")
        #expect(EQBands.label(for: 16000) == "16k")
    }

    @Test func applyClampsGainsAndSetsBypass() {
        let eq = AVAudioUnitEQ(numberOfBands: 4)
        EQBands.apply(gainsDB: [20, -20, 5, 0], isEnabled: false, to: eq)
        #expect(eq.bands[0].gain == EQBands.maxGainDB)   // 20 borné à +12
        #expect(eq.bands[1].gain == EQBands.minGainDB)   // -20 borné à -12
        #expect(eq.bands[2].gain == 5)
        #expect(eq.bypass == true)                       // désactivé
    }
}
