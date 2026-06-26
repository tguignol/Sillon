import SwiftUI

/// Pastille de provenance affichée en coin de pochette : logo du serveur d'origine (Jellyfin /
/// Navidrome-Subsonic, dessinés par `ServerMarks` ; symbole pour les fichiers locaux). N'apparaît
/// qu'en présence de plusieurs serveurs ACTIFS (cf. `EnvironmentValues.hasMultipleServers`), où la
/// provenance devient une information utile — avec un seul serveur actif, tout vient de la même source.
struct SourceBadge: View {
    let type: ServerType

    var body: some View {
        // Pastille sur fond blanc fixe (indépendant de l'apparence claire/sombre) : garantit le
        // contraste des logos colorés posés sur une pochette quelconque, et l'ombre les en détache.
        mark
            .padding(markPadding)
            .frame(width: 20, height: 20)
            .background(.white, in: Circle())
            .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 1.5, x: 0, y: 0.5)
            .padding(5)
            .accessibilityLabel("Source : \(type.displayName)")
    }

    @ViewBuilder private var mark: some View {
        switch type {
        case .jellyfin: JellyfinMark()
        case .subsonic:  NavidromeMark()
        case .local:
            Image(systemName: type.systemImageName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.22))
        }
    }

    /// Marge interne par marque : le vinyle remplit la pastille (bord noir propre), le triangle
    /// Jellyfin et le symbole local respirent un peu plus.
    private var markPadding: CGFloat {
        switch type {
        case .subsonic: 1.5
        case .jellyfin: 3
        case .local:    4
        }
    }
}

/// Pastille « N sources » pour un album/titre présent sur plusieurs serveurs (dédupliqué) :
/// petite pile + compteur, à la place de l'icône de source unique.
struct SourceCountBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: "square.stack.fill").font(.system(size: 8, weight: .bold))
            Text("\(count)").font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .frame(height: 20)
        .background(Color.black.opacity(0.6), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
        .padding(5)
        .accessibilityLabel("\(count) sources")
    }
}

/// Vrai dès qu'au moins deux serveurs sont **actifs** → les vues affichent alors les pastilles de
/// source pour distinguer la provenance des albums/titres (avec un seul serveur actif, tout provient
/// de la même source : les pastilles seraient redondantes et la déduplication inutile).
private struct HasMultipleServersKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var hasMultipleServers: Bool {
        get { self[HasMultipleServersKey.self] }
        set { self[HasMultipleServersKey.self] = newValue }
    }
}
