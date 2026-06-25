import SwiftUI
import SwiftData

/// File de téléchargements visible : statut et progression de chaque morceau, avec actions
/// (annuler, supprimer, réessayer). Accessible depuis Réglages ▸ Téléchargements.
struct DownloadsView: View {
    @Query(sort: \DownloadTask.queuedAt, order: .reverse) private var tasks: [DownloadTask]
    @Environment(\.modelContext) private var context
    @Environment(\.downloadManager) private var downloadManager

    var body: some View {
        Group {
            if tasks.isEmpty {
                ContentUnavailableView(
                    "Aucun téléchargement",
                    systemImage: "arrow.down.circle",
                    description: Text("Téléchargez un morceau ou un album depuis la bibliothèque pour le retrouver ici, et l'écouter hors connexion.")
                )
            } else {
                List {
                    ForEach(tasks) { task in
                        DownloadRow(task: task, track: track(for: task.trackID))
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Téléchargements")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func track(for id: String) -> Track? {
        try? context.fetch(FetchDescriptor<Track>(predicate: #Predicate { $0.id == id })).first
    }
}

private struct DownloadRow: View {
    let task: DownloadTask
    let track: Track?
    @Environment(\.downloadManager) private var downloadManager

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: task.status.systemImageName)
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(track?.title ?? "Morceau")
                    .font(Typo.corps)
                    .lineLimit(1)
                if task.status == .downloading {
                    ProgressView(value: task.progressFraction)
                        .progressViewStyle(.linear)
                    Text("\(Int(task.progressFraction * 100)) %")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Text(subtitle)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(task.status == .failed ? .red : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            trailingAction
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        switch task.status {
        case .failed: return task.errorMessage ?? "Échec"
        case .downloaded: return "Téléchargé"
        case .queued: return "En attente"
        default: return task.status.label
        }
    }

    private var tint: Color {
        switch task.status {
        case .downloaded: return Palette.signalTeal
        case .failed: return .red
        default: return Palette.accentCuivre
        }
    }

    @ViewBuilder private var trailingAction: some View {
        if let track, let downloadManager {
            switch task.status {
            case .downloading, .queued:
                Button {
                    downloadManager.cancel(track)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            case .failed:
                Button("Réessayer") {
                    Task { await downloadManager.enqueue(track) }
                }
                .buttonStyle(.bordered)
            case .downloaded:
                Button {
                    downloadManager.removeDownload(track)
                } label: {
                    Image(systemName: "trash").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            case .notDownloaded:
                EmptyView()
            }
        }
    }
}

#Preview {
    NavigationStack { DownloadsView() }
        .modelContainer(SillonSchema.makeContainer(inMemory: true))
}
