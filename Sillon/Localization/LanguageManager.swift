import Foundation
import SwiftUI

/// Langues proposées par l'app : « Automatique » (suit l'appareil) + les 10 langues les plus parlées
/// en Suisse (4 langues nationales + langues d'immigration/internationales majeures).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case fr, de, it, en, pt, sq, es, sr, rm, tr

    var id: String { rawValue }

    /// Code de localisation (`.lproj`) ; `nil` pour « Automatique » (langue de l'appareil).
    var localeCode: String? { self == .system ? nil : rawValue }

    /// Nom affiché dans le sélecteur, écrit DANS la langue elle-même (façon réglages iOS).
    /// « Automatique » est localisé (clé traduite), les autres restent en endonyme.
    var displayName: String {
        switch self {
        case .system: return LanguageManager.string("Automatique (langue du système)")
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .it: return "Italiano"
        case .en: return "English"
        case .pt: return "Português"
        case .sq: return "Shqip"
        case .es: return "Español"
        case .sr: return "Srpski"
        case .rm: return "Rumantsch"
        case .tr: return "Türkçe"
        }
    }
}

/// `Bundle` dont la résolution de chaînes peut être redirigée vers un `.lproj` choisi à l'exécution.
/// On échange la classe de `Bundle.main` pour celle-ci afin de changer la langue de l'app SANS
/// redémarrage : `Text("…")`, `Label`, `String(localized:)`… passent tous par `localizedString(forKey:)`.
final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = objc_getAssociatedObject(self, &LanguageManager.bundleKey) as? Bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

enum LanguageManager {
    static let storageKey = "appLanguage"
    nonisolated(unsafe) static var bundleKey: UInt8 = 0

    /// Langue actuellement choisie dans les réglages.
    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    /// `Locale` à injecter dans l'environnement SwiftUI (formats dates/nombres cohérents avec la langue).
    static var locale: Locale {
        current.localeCode.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
    }

    /// À appeler une fois au lancement : échange la classe de `Bundle.main` et applique la langue choisie.
    static func bootstrap() {
        object_setClass(Bundle.main, LocalizedBundle.self)
        apply(current)
    }

    /// Chaîne traduite respectant la langue CHOISIE dans l'app. À utiliser pour tout texte hors
    /// `LocalizedStringKey` (labels d'enum, messages d'erreur…) : `String(localized:)` suit la langue
    /// SYSTÈME et ignore notre redirection de bundle, alors que ce passe-plat passe par
    /// `Bundle.main` (redirigé) comme `Text`/`Label`.
    static func string(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    /// Variante avec arguments de format (la clé porte les spécificateurs `%@` / `%lld` / `%d`).
    static func string(_ key: String, _ args: CVarArg...) -> String {
        String(format: Bundle.main.localizedString(forKey: key, value: key, table: nil), locale: locale, arguments: args)
    }

    /// Redirige `Bundle.main` vers le `.lproj` de la langue (ou supprime la redirection pour « Automatique »).
    static func apply(_ language: AppLanguage) {
        let target: Bundle?
        if let code = language.localeCode, let path = Bundle.main.path(forResource: code, ofType: "lproj") {
            target = Bundle(path: path)
        } else {
            target = nil   // Automatique → résolution par défaut (langue de l'appareil)
        }
        objc_setAssociatedObject(Bundle.main, &bundleKey, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
