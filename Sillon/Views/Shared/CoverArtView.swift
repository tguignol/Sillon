import SwiftUI

/// Pochette carrée réutilisable : tente de charger l'artwork réel du serveur, retombe sur un
/// placeholder cuivré déterministe (dégradé dérivé du `seed`) en cas d'absence d'image.
///
/// Élément central de l'esthétique "disquaire" : même sans cover art (fichiers locaux, serveur
/// dépourvu d'images), la grille reste intentionnelle plutôt que vide.
struct CoverArtView: View {
    let path: String?
    let server: ServerAccount?
    /// Graine de couleur du placeholder (ex: titre d'album) — stable d'un écran à l'autre.
    let seed: String
    var symbol: String = "music.note"
    /// Taille de vignette demandée au serveur (px). N'impose pas la taille d'affichage SwiftUI.
    var preferredSize: Int = 256

    @Environment(\.artworkLoader) private var loader
    @State private var resolvedURL: URL?
    @State private var didResolve = false

    var body: some View {
        ZStack {
            placeholder
            if let resolvedURL {
                AsyncImage(url: resolvedURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill().transition(.opacity)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCorner, style: .continuous))
        .task(id: taskID) {
            guard !didResolve else { return }
            didResolve = true
            resolvedURL = await loader.coverURL(path: path, server: server, size: preferredSize)
        }
    }

    private var taskID: String { "\(server?.id.uuidString ?? "-")|\(path ?? "-")" }

    private var placeholder: some View {
        Palette.placeholderGradient(seed: seed)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Palette.texteIvoire.opacity(0.35))
            )
    }
}

#Preview {
    HStack(spacing: 12) {
        CoverArtView(path: nil, server: nil, seed: "Kind of Blue")
        CoverArtView(path: nil, server: nil, seed: "OK Computer")
        CoverArtView(path: nil, server: nil, seed: "Random Access Memories", symbol: "person.fill")
    }
    .frame(height: 120)
    .padding()
    .background(Palette.fondNoir)
}
