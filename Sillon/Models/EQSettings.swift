import Foundation
import SwiftData

/// Mode d'édition de l'égaliseur (l'EQ appliqué est paramétrique dans tous les cas) :
/// - `normal` : curseurs verticaux, bandes à fréquences fixes (log) et largeur fixe → gain seul ;
/// - `parametric` : fréquence + largeur (octaves) + gain réglables par bande (cartes numériques) ;
/// - `graphic` : courbe de réponse, une poignée par bande glissée à la main (façon Sennheiser Smart Control).
/// Ordre d'affichage des onglets = ordre de déclaration.
enum EQMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal
    case parametric
    case graphic
    var id: String { rawValue }
    var label: String {
        switch self {
        case .normal: LanguageManager.string("Normal")
        case .parametric: LanguageManager.string("Paramétrique")
        case .graphic: LanguageManager.string("Graphique")
        }
    }
}

/// État courant de l'égaliseur.
///
/// Décision documentée : le prompt mentionne à la fois "presets EQ utilisateur" (section Stack)
/// et "pas de presets nommés" (section Fonctionnalités, point 8). On retient l'interprétation
/// la plus contraignante et explicite : un seul état EQ persistant (singleton), pas de presets
/// multiples nommés. Si des presets nommés sont souhaités, ce sera proposé comme item Phase 2.
@Model
final class EQSettings {
    @Attribute(.unique) var id: UUID
    var bandCount: Int        // 6...12, défaut 8
    var gainsDB: [Double]     // une valeur par bande, -12.0...12.0
    var isEnabled: Bool
    var updatedAt: Date

    /// Mode d'édition courant. Stocké en brut (String) → migration légère.
    var modeRaw: String = EQMode.normal.rawValue
    /// Paramétrique : fréquence centrale (Hz) par bande. Vide ou taille ≠ bandCount ⇒ défauts log.
    var frequencies: [Double] = []
    /// Paramétrique : largeur de bande (octaves) par bande. Vide ou taille ≠ bandCount ⇒ 1.0.
    var bandwidths: [Double] = []

    var mode: EQMode {
        get { EQMode(rawValue: modeRaw) ?? .graphic }
        set { modeRaw = newValue.rawValue }
    }

    /// Identifiant fixe : un seul enregistrement `EQSettings` doit exister dans la base.
    /// La création/récupération de cet unique enregistrement est gérée par un repository
    /// (introduit à l'étape "Égaliseur"), pas directement par ce modèle.
    static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    init(bandCount: Int = 8) {
        precondition((6...12).contains(bandCount), "bandCount doit être compris entre 6 et 12.")
        self.id = EQSettings.singletonID
        self.bandCount = bandCount
        self.gainsDB = Array(repeating: 0, count: bandCount)
        self.isEnabled = true
        self.updatedAt = .now
    }
}

extension EQSettings {
    /// Lecture bornée du gain d'une bande : renvoie 0 si l'index est hors plage. Indispensable car
    /// après une réduction du nombre de bandes, SwiftUI ré-évalue brièvement la ligne en cours de
    /// suppression avec un index désormais hors bornes (le tableau `gainsDB` a déjà rétréci) — sans
    /// cette garde l'accès `gainsDB[index]` lèverait « Index out of range » et planterait l'app.
    func gain(at index: Int) -> Double {
        gainsDB.indices.contains(index) ? gainsDB[index] : 0
    }
}
