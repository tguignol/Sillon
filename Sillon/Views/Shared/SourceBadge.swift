import SwiftUI

/// Pastille de provenance affichée en coin de pochette : petite icône du type de serveur
/// (Jellyfin / Navidrome-Subsonic / fichiers locaux). N'apparaît qu'en présence de plusieurs
/// serveurs (cf. `EnvironmentValues.hasMultipleServers`), où la source devient une information utile.
struct SourceBadge: View {
    let type: ServerType

    var body: some View {
        // Scrim média : couleurs FIXES (indépendantes de l'apparence claire/sombre), comme un overlay
        // posé sur une pochette — sinon le badge vire au blanc-sur-blanc en mode clair.
        Image(systemName: type.systemImageName)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Color.black.opacity(0.55), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
            .padding(5)
            .accessibilityLabel("Source : \(type.displayName)")
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

/// Vrai dès qu'au moins deux serveurs sont configurés → les vues affichent alors les pastilles de
/// source pour distinguer la provenance des albums/titres.
private struct HasMultipleServersKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var hasMultipleServers: Bool {
        get { self[HasMultipleServersKey.self] }
        set { self[HasMultipleServersKey.self] = newValue }
    }
}
