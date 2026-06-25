import SwiftUI

struct ServerRowView: View {
    let server: ServerAccount
    let syncState: ServerListViewModel.SyncState
    let onSyncTapped: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: server.type.systemImageName)
                .font(.title3)
                .foregroundStyle(Palette.accentCuivre)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.headline)
                Text(subtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            trailingControl
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var trailingControl: some View {
        switch syncState {
        case .idle:
            Button("Synchroniser", action: onSyncTapped)
                .buttonStyle(.bordered)
        case .syncing(let progress):
            VStack(alignment: .trailing, spacing: 4) {
                if progress.total > 0 {
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 90)
                } else {
                    ProgressView()
                }
                Text(Self.label(for: progress))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Button(action: onSyncTapped) {
                Label("Réessayer", systemImage: "exclamationmark.triangle.fill")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .help(message)
        }
    }

    private static func label(for progress: LibrarySyncService.Progress) -> String {
        switch progress.phase {
        case .authenticating: return "Connexion…"
        case .fetchingLibrary: return "Analyse complète…"
        case .fetchingDelta: return "Mise à jour…"
        case .applying:
            return progress.total > 0 ? "\(progress.processed)/\(progress.total)" : "Écriture…"
        case .done: return "Terminé"
        }
    }

    private var subtitle: String {
        if let lastSync = server.lastDeltaSyncDate {
            return "Dernière synchro : \(lastSync.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Jamais synchronisé"
    }
}

#Preview {
    List {
        ServerRowView(
            server: ServerAccount(name: "Mon Jellyfin", type: .jellyfin, baseURLString: "https://exemple.local", username: "alex"),
            syncState: .idle,
            onSyncTapped: {}
        )
        ServerRowView(
            server: ServerAccount(name: "Navidrome maison", type: .subsonic, baseURLString: "https://exemple.local", username: "alex"),
            syncState: .syncing(.init(phase: .applying, processed: 120, total: 480)),
            onSyncTapped: {}
        )
        ServerRowView(
            server: ServerAccount(name: "Disque externe", type: .local),
            syncState: .failed("Dossier introuvable"),
            onSyncTapped: {}
        )
    }
}
