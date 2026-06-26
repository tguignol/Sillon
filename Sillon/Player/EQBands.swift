import Foundation
import AVFoundation

/// Disposition des bandes de l'égaliseur : fréquences centrales réparties logarithmiquement entre
/// 32 Hz et 16 kHz, conformément à un égaliseur graphique classique. Le nombre de bandes (6…12)
/// vient de `EQSettings`.
enum EQBands {
    static let minGainDB: Float = -12
    static let maxGainDB: Float = 12

    /// Fréquences centrales pour un nombre de bandes donné (réparties en log).
    static func frequencies(count: Int) -> [Float] {
        let clamped = max(2, count)
        let low = log2(32.0)
        let high = log2(16_000.0)
        let step = (high - low) / Double(clamped - 1)
        return (0..<clamped).map { Float(pow(2.0, low + step * Double($0))) }
    }

    /// Étiquette compacte d'une fréquence (ex: "60", "1k", "16k").
    static func label(for frequency: Float) -> String {
        if frequency >= 1000 {
            let k = frequency / 1000
            return k == k.rounded() ? "\(Int(k))k" : String(format: "%.1fk", k)
        }
        return "\(Int(frequency.rounded()))"
    }

    /// Applique les réglages à l'unité EQ. Les filtres AVAudioUnitEQ sont toujours `.parametric` ;
    /// le mode « Normal » fige fréquences (log) et largeur (1 octave) et n'expose que le gain, tandis
    /// que le mode « Paramétrique » applique les fréquences/largeurs réglées par l'utilisateur.
    static func apply(_ settings: EQSettings, to eq: AVAudioUnitEQ) {
        let count = eq.bands.count
        let isParam = settings.mode == .parametric
        let freqs: [Float] = (isParam && settings.frequencies.count == count)
            ? settings.frequencies.map { Float($0) }
            : frequencies(count: count)
        let bws: [Float] = (isParam && settings.bandwidths.count == count)
            ? settings.bandwidths.map { Float($0) }
            : Array(repeating: 1.0, count: count)

        for (index, band) in eq.bands.enumerated() {
            band.filterType = .parametric
            if index < freqs.count { band.frequency = max(20, min(20_000, freqs[index])) }
            band.bandwidth = index < bws.count ? max(0.05, min(5.0, bws[index])) : 1.0
            let gain = index < settings.gainsDB.count ? Float(settings.gainsDB[index]) : 0
            band.gain = min(maxGainDB, max(minGainDB, gain))
            band.bypass = false
        }
        eq.globalGain = 0
        eq.bypass = !settings.isEnabled
    }
}
