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
        item.isFavorite.toggle()
        item.favoriteDate = item.isFavorite ? .now : nil
        try? context.save()
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
