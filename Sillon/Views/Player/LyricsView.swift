import SwiftUI

/// Affiche les paroles du morceau en cours, récupérées à la demande via `LyricsLoader`.
/// - Synchronisées : surligne la ligne courante selon `player.currentTime`, auto-défile, et permet
///   un seek au tap sur une ligne.
/// - Non synchronisées : simple texte défilable.
/// Intégré DANS le lecteur (à la place de la pochette) pour garder le transport accessible.
struct LyricsView: View {
    let track: Track

    @Environment(\.lyricsLoader) private var loader
    @State private var lyrics: TrackLyrics?
    @State private var didLoad = false

    var body: some View {
        Group {
            if let lyrics, !lyrics.lines.isEmpty {
                if lyrics.synced {
                    SyncedLyricsView(lines: lyrics.lines)
                } else {
                    PlainLyricsView(lines: lyrics.lines)
                }
            } else if didLoad {
                ContentUnavailableView("Pas de paroles", systemImage: "quote.bubble")
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: track.id) {
            didLoad = false
            lyrics = await loader.lyrics(for: track)
            didLoad = true
        }
    }
}

/// Paroles non synchronisées : texte ivoire, simplement défilable.
private struct PlainLyricsView: View {
    let lines: [LyricLine]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(Typo.corps)
                        .foregroundStyle(Palette.texteIvoire)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.l)
        }
    }
}

/// Paroles synchronisées : surligne la ligne courante (cuivre), auto-défile pour la centrer,
/// tap sur une ligne = seek à son timecode.
private struct SyncedLyricsView: View {
    @Environment(\.playerController) private var player
    let lines: [LyricLine]

    var body: some View {
        // currentTime change ~à chaque tick : l'Observable redéclenche ce body (comme le Slider du lecteur).
        let active = TrackLyrics(synced: true, lines: lines).activeLineIndex(at: player?.currentTime ?? 0)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.l) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        lineView(line: line, isActive: index == active)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let t = line.timeSeconds { player?.seek(to: t) }
                            }
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, 40)   // marges pour centrer la 1re et la dernière ligne (zone intégrée)
            }
            .scrollIndicators(.hidden)
            .onChange(of: active) { _, newValue in
                guard let i = newValue else { return }
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(i, anchor: .center) }
            }
            .onAppear {
                if let i = active { proxy.scrollTo(i, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func lineView(line: LyricLine, isActive: Bool) -> some View {
        Text(line.text.isEmpty ? "♪" : line.text)
            .font(isActive ? Typo.displaySmall : Typo.corps)
            .foregroundStyle(isActive ? Palette.accentCuivre : Palette.texteSourdine)
            .opacity(isActive ? 1 : 0.55)
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(isActive ? 1.0 : 0.98, anchor: .leading)
            .animation(.easeInOut(duration: 0.3), value: isActive)
            .padding(.vertical, Spacing.xs)
    }
}
