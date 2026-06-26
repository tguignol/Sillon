import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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
    // Couleurs ADAPTATIVES : variante claire / sombre choisie selon l'apparence effective de l'app.
    // En mode sombre (apparence par défaut), les valeurs `dark` reproduisent à l'identique la palette
    // d'origine — aucun changement visuel. Le mode clair garde l'esthétique chaude « disquaire ».

    /// Fond principal.
    static let fondNoir = Color(light: 0xF6F4EF, dark: 0x0B0D0F)
    /// Cartes, feuilles modales, lignes survolées.
    static let surfaceElevee = Color(light: 0xFFFFFF, dark: 0x15181B)
    /// Accent principal : cœur favori, lecture en cours, AccentColor système.
    static let accentCuivre = Color(light: 0xB06D2C, dark: 0xD98E4A)
    /// Réservé aux données techniques : EQ actif, indicateur de sync, badges codec.
    static let signalTeal = Color(light: 0x2E7D75, dark: 0x4FA8A0)
    /// Texte principal (clair sur fond sombre ; sombre chaud sur fond clair).
    static let texteIvoire = Color(light: 0x1C1A17, dark: 0xF3F1EC)
    /// Texte secondaire, légendes, métadonnées.
    static let texteSourdine = Color(light: 0x6E6A64, dark: 0x9A9590)

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

    /// Couleur dynamique : variante claire / sombre résolue selon l'apparence effective (système ou
    /// forcée par le réglage de l'app). Garde la palette en code, sans catalogue d'assets.
    init(light: UInt32, dark: UInt32) {
        #if os(iOS)
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #elseif os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
        #else
        self.init(hex: dark)
        #endif
    }
}

// MARK: - Apparence (clair / sombre / système)

/// Réglage d'apparence de l'app. `colorScheme == nil` => suit le système.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case systeme, clair, sombre
    var id: String { rawValue }
    var label: String {
        switch self {
        case .systeme: LanguageManager.string("Système")
        case .clair:   LanguageManager.string("Clair")
        case .sombre:  LanguageManager.string("Sombre")
        }
    }
    var systemImage: String {
        switch self {
        case .systeme: "circle.lefthalf.filled"
        case .clair:   "sun.max"
        case .sombre:  "moon"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .systeme: nil
        case .clair:   .light
        case .sombre:  .dark
        }
    }
}
