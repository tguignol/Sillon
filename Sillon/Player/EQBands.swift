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

    /// Applique les réglages à l'unité EQ : type paramétrique, gains bornés, bypass global.
    static func apply(gainsDB: [Double], isEnabled: Bool, to eq: AVAudioUnitEQ) {
        let frequencies = frequencies(count: eq.bands.count)
        for (index, band) in eq.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = index < frequencies.count ? frequencies[index] : band.frequency
            band.bandwidth = 1.0   // octaves
            let gain = index < gainsDB.count ? Float(gainsDB[index]) : 0
            band.gain = min(maxGainDB, max(minGainDB, gain))
            band.bypass = false
        }
        eq.globalGain = 0
        eq.bypass = !isEnabled
    }
}
