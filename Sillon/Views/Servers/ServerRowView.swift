import SwiftUI

struct ServerRowView: View {
    let server: ServerAccount
    let syncState: ServerListViewModel.SyncState
    let onSyncTapped: () -> Void
    /// Bascule actif/inactif : masque ou réaffiche les contenus du serveur dans la bibliothèque.
    var onSetActive: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 12) {
            typeIcon
                .frame(width: 30, height: 30)
                .opacity(server.isActive ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.headline)
                Text(subtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .opacity(server.isActive ? 1 : 0.4)

            Spacer()

            // Activer/désactiver le serveur dans la bibliothèque (non destructif).
            Toggle("Serveur actif", isOn: Binding(get: { server.isActive }, set: { onSetActive($0) }))
                .labelsHidden()
                .tint(Palette.signalTeal)

            trailingControl
        }
        .padding(.vertical, 4)
    }

    /// Icône du serveur : logo Jellyfin / vinyle Navidrome (cf. `ServerMarks`), ou symbole SF cuivré
    /// pour un dossier local (pas de logo de marque).
    @ViewBuilder private var typeIcon: some View {
        switch server.type {
        case .jellyfin: JellyfinMark()
        case .subsonic:  NavidromeMark()
        case .local:
            Image(systemName: server.type.systemImageName)
                .font(.title3)
                .foregroundStyle(Palette.accentCuivre)
        }
    }

    @ViewBuilder private var trailingControl: some View {
        switch syncState {
        case .idle:
            Button("Synchroniser", action: onSyncTapped)
                .buttonStyle(.bordered)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
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
        case .authenticating: return LanguageManager.string("Connexion…")
        case .fetchingLibrary: return LanguageManager.string("Analyse complète…")
        case .fetchingDelta: return LanguageManager.string("Mise à jour…")
        case .applying:
            return progress.total > 0 ? "\(progress.processed)/\(progress.total)" : LanguageManager.string("Écriture…")
        case .fetchingArtwork:
            return progress.total > 0 ? LanguageManager.string("Pochettes %lld/%lld", progress.processed, progress.total) : LanguageManager.string("Pochettes…")
        case .done: return LanguageManager.string("Terminé")
        }
    }

    private var subtitle: String {
        if let lastSync = server.lastDeltaSyncDate {
            return LanguageManager.string("Dernière synchro : %@", lastSync.formatted(date: .abbreviated, time: .shortened))
        }
        return LanguageManager.string("Jamais synchronisé")
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
