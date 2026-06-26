import Foundation
import SwiftData

/// Preset d'égaliseur : 4 emplacements par mode (Normal / Paramétrique / Graphique), nommables.
/// Stocke un instantané complet des réglages (nombre de bandes, gains, fréquences, largeurs).
@Model
final class EQPreset {
    var modeRaw: String      // EQMode (graphic / parametric)
    var slot: Int            // 1...4
    var name: String
    var bandCount: Int
    var gainsDB: [Double]
    var frequencies: [Double]
    var bandwidths: [Double]
    var updatedAt: Date

    var mode: EQMode { EQMode(rawValue: modeRaw) ?? .graphic }

    init(mode: EQMode, slot: Int) {
        self.modeRaw = mode.rawValue
        self.slot = slot
        self.name = "Réglage \(slot)"
        self.bandCount = 8
        self.gainsDB = Array(repeating: 0, count: 8)
        self.frequencies = []   // vide ⇒ défauts log appliqués à la lecture
        self.bandwidths = []
        self.updatedAt = .now
    }
}

/// Crée à la demande les 4 presets par défaut de chaque mode (« Réglage 1…4 »).
@MainActor
enum EQPresetStore {
    static func ensure(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<EQPreset>())) ?? []
        var created = false
        for mode in EQMode.allCases {
            for slot in 1...4 where !existing.contains(where: { $0.modeRaw == mode.rawValue && $0.slot == slot }) {
                context.insert(EQPreset(mode: mode, slot: slot))
                created = true
            }
        }
        if created { try? context.save() }
    }
}
