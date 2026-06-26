import SwiftUI
import SwiftData

/// Éléments pouvant être mis en favori. `Artist`, `Album`, `Track` portent déjà `isFavorite` /
/// `favoriteDate` (cf. Docs/DECISIONS.md #3 : propriété, pas modèle séparé) ; ce protocole unifie
/// simplement le geste de bascule.
@MainActor
protocol Favoritable: AnyObject {
    var isFavorite: Bool { get set }
    var favoriteDate: Date? { get set }
}

extension Artist: Favoritable {}
extension Album: Favoritable {}
extension Track: Favoritable {}

@MainActor
enum Favorites {
    static func toggle(_ item: Favoritable, context: ModelContext) {
        setFavorite(!item.isFavorite, on: item, context: context)
    }

    /// Pose l'état favori sur l'élément ET toutes ses copies sur d'autres serveurs (mêmes clés de
    /// dédup), pour que le favori reste cohérent quelle que soit la copie affichée comme représentante
    /// (sinon, changer la priorité serveur ferait « disparaître » le favori).
    static func setFavorite(_ value: Bool, on item: Favoritable, context: ModelContext) {
        let date: Date? = value ? .now : nil
        for target in [item] + duplicates(of: item, context: context) {
            target.isFavorite = value
            target.favoriteDate = date
        }
        try? context.save()
    }

    private static func duplicates(of item: Favoritable, context: ModelContext) -> [Favoritable] {
        switch item {
        case let album as Album: return DuplicateResolver.albumCopies(of: album, in: context).filter { $0 !== album }
        case let track as Track: return DuplicateResolver.trackCopies(of: track, in: context).filter { $0 !== track }
        case let artist as Artist: return DuplicateResolver.artistCopies(of: artist, in: context).filter { $0 !== artist }
        default: return []
        }
    }
}

/// Bouton cœur réutilisable. L'état (`isFavorite`) est passé par l'appelant — qui lit la propriété
/// observée du modèle concret, garantissant le rafraîchissement de l'UI au changement.
struct FavoriteButton: View {
    let isFavorite: Bool
    var prominent: Bool = false
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(prominent ? .title3 : .caption)
                .foregroundStyle(isFavorite ? Palette.accentCuivre : (prominent ? Palette.texteIvoire : Color.secondary))
        }
        .buttonStyle(.plain)
    }
}
