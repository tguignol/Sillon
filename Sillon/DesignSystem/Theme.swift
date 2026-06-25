import SwiftUI

/// Système de design centralisé — concrétise `Docs/DESIGN_SYSTEM.md` en constantes Swift.
///
/// Toute l'UI doit dériver de ces tokens plutôt que d'utiliser des valeurs ad hoc dispersées
/// dans les vues. Introduit au commit "Synchronisation + Bibliothèque", premier commit où de
/// vraies vues riches (cartes d'album, sections d'accueil) sont construites.
///
/// Tension fondatrice (cf. doc) : chaleur cuivrée pour la musique / le cover art, froid technique
/// (monospace + teal) réservé aux données — bitrate, codec, horodatages de sync.

// MARK: - Palette

enum Palette {
    /// Fond principal (dark natif, légèrement bleuté froid).
    static let fondNoir = Color(hex: 0x0B0D0F)
    /// Cartes, feuilles modales, lignes survolées.
    static let surfaceElevee = Color(hex: 0x15181B)
    /// Accent principal : cœur favori, lecture en cours, AccentColor système.
    static let accentCuivre = Color(hex: 0xD98E4A)
    /// Réservé aux données techniques : EQ actif, indicateur de sync, badges codec.
    static let signalTeal = Color(hex: 0x4FA8A0)
    /// Texte principal (blanc cassé chaud, évoque le papier de pochette).
    static let texteIvoire = Color(hex: 0xF3F1EC)
    /// Texte secondaire, légendes, métadonnées.
    static let texteSourdine = Color(hex: 0x9A9590)

    /// Dégradé de repli utilisé par les pochettes manquantes — garde l'esthétique "disquaire"
    /// même sans image distante (fichiers locaux, serveur sans cover art).
    static func placeholderGradient(seed: String) -> LinearGradient {
        // Teinte déterministe dérivée du seed : deux albums distincts ont des nuances différentes,
        // mais un même album garde toujours la même couleur d'un écran à l'autre.
        let hue = Double(abs(seed.hashValue) % 360) / 360.0
        let base = Color(hue: hue, saturation: 0.28, brightness: 0.34)
        let dark = Color(hue: hue, saturation: 0.35, brightness: 0.18)
        return LinearGradient(colors: [base, dark], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Typographie

enum Typo {
    /// Titres d'album, nom d'artiste en grand. Empattement système, sans dépendance externe.
    static let display = Font.system(.title, design: .serif)
    static let displaySmall = Font.system(.title3, design: .serif).weight(.medium)
    /// Corps / UI : SF Pro neutre.
    static let corps = Font.system(.body, design: .default)
    /// Donnée technique (bitrate, codec, dB, horodatage de sync) : signale visuellement
    /// "ceci est une donnée technique", distinct du reste de l'UI.
    static let technique = Font.system(.caption, design: .monospaced)
}

extension View {
    /// Style standard pour une donnée technique (codec, bitrate, horodatage de sync).
    func techniqueData() -> some View {
        font(Typo.technique).foregroundStyle(Palette.signalTeal)
    }
}

// MARK: - Espacement

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    /// Rayon d'angle standard des cartes (pochettes, sections).
    static let cardCorner: CGFloat = 10
}

// MARK: - Color hex helper

extension Color {
    /// Construit une couleur depuis un littéral hexadécimal `0xRRGGBB`. Évite des `Color` d'assets
    /// pour garder la palette versionnée en code, lisible et diffable.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
