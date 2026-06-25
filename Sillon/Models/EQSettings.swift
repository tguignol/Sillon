import Foundation
import SwiftData

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
