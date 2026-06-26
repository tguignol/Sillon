import Foundation

/// Entités de bibliothèque rattachées à un serveur. Permet de filtrer de façon uniforme par
/// serveurs actifs, sans dupliquer la logique dans chaque vue.
///
/// Choix : filtrage EN MÉMOIRE sur les résultats des `@Query` (qui agrègent déjà tous les serveurs),
/// plutôt qu'un `#Predicate` — ces derniers, dès qu'ils touchent l'`id` composite ou la relation
/// `server`, trappent à l'exécution sous SwiftData (cf. note dans LibrarySyncService). Si la
/// bibliothèque grossit au point que ce filtre pèse, on dénormalisera un drapeau sur les entités.
protocol ServerScoped {
    var server: ServerAccount? { get }
}

extension Album: ServerScoped {}
extension Track: ServerScoped {}
extension Artist: ServerScoped {}

extension Collection where Element: ServerScoped {
    /// Ne conserve que les éléments issus d'un serveur actif. Un élément sans serveur (défensif,
    /// ne devrait pas arriver) est conservé.
    ///
    /// Court-circuit : si aucun élément n'est issu d'un serveur inactif (cas ultra-majoritaire —
    /// tous les serveurs actifs), on renvoie une copie directe sans exécuter le filtre élément par
    /// élément. Évite une passe coûteuse sur de grandes listes (ex. ~16k titres).
    func onActiveServers() -> [Element] {
        guard contains(where: { !($0.server?.isActive ?? true) }) else { return Array(self) }
        return filter { $0.server?.isActive ?? true }
    }
}
