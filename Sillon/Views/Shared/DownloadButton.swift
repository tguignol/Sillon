import SwiftUI

/// Bouton de téléchargement d'un morceau, reflétant `Track.downloadStatus` et déclenchant l'action
/// adaptée (télécharger / annuler / réessayer). Masqué pour les serveurs `.local` (déjà sur disque)
/// et si aucun `DownloadManager` n'est injecté (Previews).
struct DownloadButton: View {
    let track: Track
    @Environment(\.downloadManager) private var downloadManager

    var body: some View {
        if let downloadManager, track.server?.type != .local {
            Button { handleTap(downloadManager) } label: { icon }
                .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var icon: some View {
        switch track.downloadStatus {
        case .notDownloaded:
            Image(systemName: "arrow.down.circle").font(.caption).foregroundStyle(.secondary)
        case .queued:
            Image(systemName: "clock").font(.caption).foregroundStyle(Palette.accentCuivre)
        case .downloading:
            ProgressView().controlSize(.small)
        case .downloaded:
            Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Palette.signalTeal)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
        }
    }

    private func handleTap(_ manager: DownloadManager) {
        switch track.downloadStatus {
        case .notDownloaded, .failed:
            Task { await manager.enqueue(track) }
        case .queued, .downloading:
            manager.cancel(track)
        case .downloaded:
            break   // la suppression se fait depuis l'écran Téléchargements
        }
    }
}
