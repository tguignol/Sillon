import SwiftUI

/// Lettres de l'index : A → Z, puis « # » pour les libellés non alphabétiques.
let azLetters: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ") + ["#"]

/// Première lettre normalisée d'un libellé (A–Z), ou « # » si ça ne commence pas par une lettre.
func azIndexLetter(_ label: String) -> Character {
    guard let first = label.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "#" }
    let c = Character(first.uppercased())
    return ("A"..."Z").contains(c) ? c : "#"
}

/// Index cible dans la liste ordonnée `letters` pour la lettre `c` : correspondance exacte, sinon la
/// lettre présente la plus proche dans le sens d'affichage (`ascending`), sinon une extrémité.
func azTargetIndex(in letters: [Character], for c: Character, ascending: Bool) -> Int {
    if let exact = letters.firstIndex(of: c) { return exact }
    if c == "#" { return letters.firstIndex(of: "#") ?? max(0, letters.count - 1) }
    if ascending {
        if let up = letters.firstIndex(where: { $0 != "#" && $0 > c }) { return up }
        return letters.firstIndex(of: "#") ?? max(0, letters.count - 1)
    } else {
        if let down = letters.firstIndex(where: { $0 != "#" && $0 < c }) { return down }
        return 0
    }
}

/// Index alphabétique vertical (façon iOS/Android Sillon), posé sur la bordure droite d'une liste.
/// Les lettres présentes dans la liste sont en cuivre/gras, les absentes estompées ; une pastille
/// cuivre marque la lettre `current` (position de défilement). Appui OU glissement → `onLetter`.
struct AZScrollIndex: View {
    let present: Set<Character>
    let current: Character
    let onLetter: (Character) -> Void

    @State private var lastIndex = -1
    /// Hauteur fixe par lettre : la bande reste COMPACTE (≈ 27×11 pt) plutôt que de remplir toute la
    /// hauteur, ce qui la garde centrée au-dessus du mini-player (dont l'inset ne réduit pas la colonne
    /// détail du NavigationSplitView). Sert aussi de pas pour mapper le geste → lettre.
    private let rowHeight: CGFloat = 11

    var body: some View {
        VStack(spacing: 0) {
            ForEach(azLetters, id: \.self) { c in
                let isCurrent = c == current
                Text(String(c))
                    .font(.system(size: 9, weight: isCurrent || present.contains(c) ? .bold : .regular))
                    .foregroundStyle(isCurrent ? Color.white
                                     : present.contains(c) ? Palette.accentCuivre
                                     : Palette.texteSourdine.opacity(0.45))
                    .frame(width: 22, height: rowHeight)
                    .background {
                        if isCurrent {
                            Circle().fill(Palette.accentCuivre).frame(width: 15, height: 15)
                        }
                    }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let idx = min(azLetters.count - 1, max(0, Int(value.location.y / rowHeight)))
                    if idx != lastIndex {
                        lastIndex = idx
                        onLetter(azLetters[idx])
                    }
                }
                .onEnded { _ in lastIndex = -1 }
        )
        .padding(.trailing, 2)
    }
}

/// Enveloppe une liste/grille défilante d'un index A–Z à droite. `ids` et `letters` sont parallèles
/// et dans l'ordre d'affichage. Le contenu défilant fourni doit identifier chaque élément par l'`id`
/// correspondant (via `ForEach(_, id:)` ou `List`) — et, pour un `ScrollView`, porter
/// `.scrollTargetLayout()` sur sa pile interne — afin que le saut (appui/glissement sur une lettre)
/// fonctionne. La pastille « lettre courante » suit le doigt sur l'index en temps réel (scrub iOS).
struct AZIndexedContainer<ID: Hashable, Content: View>: View {
    let ids: [ID]
    let letters: [Character]
    var ascending: Bool = true
    var showsIndex: Bool = true
    @ViewBuilder var content: Content

    /// Dernière lettre pointée sur l'index ; pilote la pastille (scrub).
    @State private var selected: Character?

    private var current: Character { selected ?? letters.first ?? "A" }

    var body: some View {
        ScrollViewReader { proxy in
            // safeAreaInset(.trailing) : l'index se loge dans la zone sûre (donc AU-DESSUS du
            // mini-player) et réduit la largeur du contenu pour ne pas le recouvrir.
            content.safeAreaInset(edge: .trailing, spacing: 0) {
                if showsIndex && !ids.isEmpty {
                    AZScrollIndex(present: Set(letters), current: current) { c in
                        selected = c
                        let t = azTargetIndex(in: letters, for: c, ascending: ascending)
                        if ids.indices.contains(t) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(ids[t], anchor: .top)
                            }
                        }
                    }
                }
            }
        }
    }
}
