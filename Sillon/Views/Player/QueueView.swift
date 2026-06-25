import SwiftUI

/// File d'attente de lecture : morceau en cours mis en évidence, saut direct (tap) et réordonnancement
/// par glisser-déposer.
struct QueueView: View {
    @Environment(\.playerController) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let player, !player.queue.isEmpty {
                    List {
                        ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, track in
                            row(index: index, track: track, isCurrent: index == player.currentIndex)
                                .contentShape(Rectangle())
                                .onTapGesture { player.jump(to: index); dismiss() }
                        }
                        .onMove { source, destination in player.moveQueue(from: source, to: destination) }
                    }
                    .listStyle(.plain)
                } else {
                    ContentUnavailableView("File vide", systemImage: "list.bullet")
                }
            }
            .navigationTitle("File d'attente")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                #endif
            }
            .background(Palette.fondNoir)
        }
    }

    private func row(index: Int, track: Track, isCurrent: Bool) -> some View {
        HStack(spacing: Spacing.m) {
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption).foregroundStyle(Palette.accentCuivre).frame(width: 20)
            } else {
                Text("\(index + 1)")
                    .font(Typo.technique).foregroundStyle(.secondary).frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(Typo.corps).lineLimit(1)
                    .foregroundStyle(isCurrent ? Palette.accentCuivre : Palette.texteIvoire)
                Text(track.artistNameSnapshot ?? track.album?.artist?.name ?? "")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(track.durationSeconds.asTrackDuration)
                .font(Typo.technique).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
