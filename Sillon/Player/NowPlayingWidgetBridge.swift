import Foundation
import WidgetKit

/// Pont app → widget « Lecture en cours ». L'app écrit l'état courant dans le conteneur partagé
/// (App Group `group.kohlnet.Sillon`) ; le widget (cible séparée) le relit. Les clés sont dupliquées
/// côté widget — garder les deux en phase. iOS uniquement (le widget n'existe pas sur macOS).
enum NowPlayingWidgetBridge {
    static let appGroup = "group.kohlnet.Sillon"
    static let coverFileName = "np-cover.dat"

    // Clés du conteneur partagé (UserDefaults de l'App Group).
    enum Key {
        static let has = "np.has"
        static let title = "np.title"
        static let artist = "np.artist"
        static let album = "np.album"
        static let quality = "np.quality"
        static let favorite = "np.favorite"
        static let playing = "np.playing"
        static let elapsed = "np.elapsed"
        static let duration = "np.duration"
        static let anchor = "np.anchor"   // instant (epoch) où `elapsed` a été échantillonné → progression vivante
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }
    static var coverURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(coverFileName)
    }

    /// Publie l'état texte/progression/lecture et rafraîchit le widget. `title == nil` ⇒ rien en lecture.
    static func publish(title: String?, artist: String, album: String, quality: String,
                        isFavorite: Bool, isPlaying: Bool, elapsed: Double, duration: Double) {
        #if os(iOS)
        guard let d = defaults else { return }
        if let title {
            d.set(true, forKey: Key.has)
            d.set(title, forKey: Key.title)
            d.set(artist, forKey: Key.artist)
            d.set(album, forKey: Key.album)
            d.set(quality, forKey: Key.quality)
            d.set(isFavorite, forKey: Key.favorite)
            d.set(isPlaying, forKey: Key.playing)
            d.set(elapsed, forKey: Key.elapsed)
            d.set(duration, forKey: Key.duration)
            d.set(Date().timeIntervalSince1970, forKey: Key.anchor)
        } else {
            d.set(false, forKey: Key.has)
        }
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Écrit la pochette du morceau courant dans le conteneur partagé (données image déjà téléchargées).
    static func writeCover(_ data: Data) {
        #if os(iOS)
        guard let url = coverURL else { return }
        try? data.write(to: url, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Retire la pochette partagée (au changement de morceau, avant que la nouvelle soit chargée).
    static func clearCover() {
        #if os(iOS)
        guard let url = coverURL else { return }
        try? FileManager.default.removeItem(at: url)
        #endif
    }
}
