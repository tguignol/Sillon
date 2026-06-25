import Foundation

/// Calcul (pur, testable) du facteur de gain linéaire ReplayGain à appliquer à un morceau.
///
/// Tous les gains sont en **dB** (déjà prêts à appliquer), les peaks en **ratio linéaire**
/// (~0..1, peuvent dépasser 1.0 si le master est clippé). Toutes les entrées sont optionnelles :
/// `nil` signifie « donnée inconnue » et déclenche les replis. Lecture seule — on ne fait que
/// consommer les tags lus sur le serveur, jamais les modifier.
enum ReplayGain {
    /// Facteur linéaire (0…1+) selon le mode, avec replis et protection anti-clipping.
    /// Renvoie `1.0` (neutre) si le mode est `.off` ou si aucun gain n'est disponible.
    ///
    /// Replis (jamais piste + album cumulés) :
    /// - mode `.album` : `albumGain` (par-song) → `albumRelGain` (relation Album) → `trackGain` → `fallbackGain`.
    /// - mode `.track` : `trackGain` → `fallbackGain`.
    ///
    /// Anti-clipping : si activé et le peak est connu (>0), on borne `factor ≤ 1/peak` ; si le peak
    /// est inconnu (cas Jellyfin), on n'amplifie jamais au-delà de 0 dB (`factor ≤ 1.0`).
    static func linearFactor(
        mode: ReplayGainMode,
        trackGain: Double?, trackPeak: Double?,
        albumGain: Double?, albumPeak: Double?,
        albumRelGain: Double? = nil, albumRelPeak: Double? = nil,
        fallbackGain: Double?,
        preampDB: Double,
        clipProtection: Bool
    ) -> Float {
        let gainDB: Double?
        let peak: Double?
        switch mode {
        case .off:
            return 1.0
        case .album:
            gainDB = albumGain ?? albumRelGain ?? trackGain ?? fallbackGain
            peak   = albumPeak ?? albumRelPeak ?? trackPeak
        case .track:
            gainDB = trackGain ?? fallbackGain
            peak   = trackPeak
        }
        guard let baseDB = gainDB else { return 1.0 }   // gain manquant => 0 dB (facteur neutre)

        let totalDB = baseDB + preampDB
        var factor = pow(10.0, totalDB / 20.0)

        if clipProtection {
            if let peak, peak > 0 {
                factor = min(factor, 1.0 / peak)
            } else {
                factor = min(factor, 1.0)
            }
        }
        return Float(factor)
    }
}
