import SwiftUI

struct ServerRowView: View {
    let server: ServerAccount
    let syncState: ServerListViewModel.SyncState
    let onSyncTapped: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: server.type.systemImageName)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
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
        case .syncing:
            ProgressView()
        case .failed(let message):
            Button(action: onSyncTapped) {
                Label("Réessayer", systemImage: "exclamationmark.triangle.fill")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .help(message)
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
            syncState: .syncing,
            onSyncTapped: {}
        )
        ServerRowView(
            server: ServerAccount(name: "Disque externe", type: .local),
            syncState: .failed("Dossier introuvable"),
            onSyncTapped: {}
        )
    }
}
