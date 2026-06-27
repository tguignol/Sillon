import SwiftUI
import NaturalLanguage
import Translation

/// Affiche les paroles du morceau en cours, récupérées à la demande via `LyricsLoader`.
/// - Synchronisées : surligne la ligne courante selon `player.currentTime`, auto-défile, et permet
///   un seek au tap sur une ligne.
/// - Non synchronisées : simple texte défilable.
/// Intégré DANS le lecteur (à la place de la pochette) pour garder le transport accessible.
///
/// Traduction (façon Apple Music) : un bouton « Traduire » insère, sous chaque ligne, sa traduction
/// dans la langue de l'app (Réglages ▸ Langue) en vert. La traduction est faite À LA DEMANDE et
/// SUR L'APPAREIL via le framework `Translation` d'Apple (gratuit, sans clé ni envoi réseau des
/// paroles). Le bouton n'apparaît que si la langue détectée des paroles ET la langue de l'app font
/// partie des langues prises en charge {de, fr, it, es, en} et sont différentes (paroles déjà dans
/// la langue de l'app → pas de bouton).
struct LyricsView: View {
    let track: Track

    @Environment(\.lyricsLoader) private var loader
    @State private var lyrics: TrackLyrics?
    @State private var didLoad = false

    // Traduction
    @State private var translations: [Int: String] = [:]
    @State private var showTranslation = false
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var detectedLanguage: String?

    /// Langues prises en charge pour la traduction (source détectée ET cible de l'app).
    private static let supportedLanguages: Set<String> = ["de", "fr", "it", "es", "en"]

    /// Code langue cible = langue choisie dans les Réglages (ou langue de l'appareil si « Automatique »).
    private var targetLanguage: String? {
        if let code = LanguageManager.current.localeCode { return code }
        return Locale.current.language.languageCode?.identifier
    }

    /// Le bouton « Traduire » n'est proposé que si la source détectée ET la cible sont prises en charge
    /// et différentes (paroles déjà dans la langue de l'app → rien à proposer).
    private var canTranslate: Bool {
        guard let target = targetLanguage, Self.supportedLanguages.contains(target),
              let source = detectedLanguage, Self.supportedLanguages.contains(source),
              source != target else { return false }
        return true
    }

    private var hasLyrics: Bool {
        !(lyrics?.lines.isEmpty ?? true)
    }

    var body: some View {
        Group {
            if let lyrics, !lyrics.lines.isEmpty {
                if lyrics.synced {
                    SyncedLyricsView(lines: lyrics.lines,
                                     translations: showTranslation ? translations : [:])
                } else {
                    PlainLyricsView(lines: lyrics.lines,
                                    translations: showTranslation ? translations : [:])
                }
            } else if didLoad {
                ContentUnavailableView("Pas de paroles", systemImage: "quote.bubble")
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hasLyrics, canTranslate {
                translateButton
                    .padding(.horizontal, Spacing.l)
                    .padding(.top, Spacing.s)
            }
        }
        .translationTask(translationConfig) { session in
            await runTranslation(with: session)
        }
        .task(id: track.id) {
            didLoad = false
            translations = [:]
            showTranslation = false
            translationConfig = nil
            detectedLanguage = nil
            let loaded = await loader.lyrics(for: track)
            lyrics = loaded
            detectedLanguage = Self.detectLanguage(in: loaded)
            didLoad = true
        }
    }

    private var translateButton: some View {
        Button {
            toggleTranslation()
        } label: {
            Label(showTranslation ? "Original" : "Traduire", systemImage: "character.bubble")
                .font(Typo.technique)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.xs)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(showTranslation ? Palette.signalTeal : Palette.texteIvoire)
        }
        .buttonStyle(.plain)
    }

    private func toggleTranslation() {
        if showTranslation {
            withAnimation(.easeInOut(duration: 0.25)) { showTranslation = false }
            return
        }
        withAnimation(.easeInOut(duration: 0.25)) { showTranslation = true }
        // Déclenche (ou re-déclenche) la traduction si elle n'est pas déjà disponible. Le framework
        // télécharge le modèle de langue au besoin (invite système la 1re fois).
        guard translations.isEmpty, let source = detectedLanguage, let target = targetLanguage else { return }
        translationConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: source),
            target: Locale.Language(identifier: target))
    }

    private func runTranslation(with session: TranslationSession) async {
        guard let lines = lyrics?.lines else { return }
        let requests: [TranslationSession.Request] = lines.enumerated().compactMap { index, line in
            guard !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return TranslationSession.Request(sourceText: line.text, clientIdentifier: String(index))
        }
        guard !requests.isEmpty else { return }
        do {
            let responses = try await session.translations(from: requests)
            var map: [Int: String] = [:]
            for response in responses {
                if let id = response.clientIdentifier, let index = Int(id) {
                    map[index] = response.targetText
                }
            }
            translations = map
        } catch {
            // Modèle indisponible / téléchargement refusé / erreur : on garde les paroles d'origine.
            // On remet la config à nil pour qu'un nouveau tap puisse relancer la tentative.
            translationConfig = nil
            withAnimation(.easeInOut(duration: 0.25)) { showTranslation = false }
        }
    }

    /// Langue dominante des paroles (code BCP-47 : « en », « fr »…), détectée sur l'appareil.
    private static func detectLanguage(in lyrics: TrackLyrics?) -> String? {
        guard let lyrics else { return nil }
        let text = lyrics.lines.map(\.text).joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }
}

/// Paroles non synchronisées : texte ivoire, simplement défilable. La traduction (si présente) s'affiche
/// en vert sous chaque ligne.
private struct PlainLyricsView: View {
    let lines: [LyricLine]
    var translations: [Int: String] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(Typo.corps)
                            .foregroundStyle(Palette.texteIvoire)
                        if let translated = translations[index], !translated.isEmpty {
                            Text(translated)
                                .font(Typo.corps)
                                .foregroundStyle(Palette.signalTeal)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.l)
        }
    }
}

/// Paroles synchronisées : surligne la ligne courante (cuivre), auto-défile pour la centrer,
/// tap sur une ligne = seek à son timecode. La traduction (si présente) s'affiche en vert sous la ligne.
private struct SyncedLyricsView: View {
    @Environment(\.playerController) private var player
    let lines: [LyricLine]
    var translations: [Int: String] = [:]

    var body: some View {
        // currentTime change ~à chaque tick : l'Observable redéclenche ce body (comme le Slider du lecteur).
        let active = TrackLyrics(synced: true, lines: lines).activeLineIndex(at: player?.currentTime ?? 0)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.l) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        lineView(line: line, isActive: index == active, translated: translations[index])
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
    private func lineView(line: LyricLine, isActive: Bool, translated: String?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(line.text.isEmpty ? "♪" : line.text)
                .font(isActive ? Typo.displaySmall : Typo.corps)
                .foregroundStyle(isActive ? Palette.accentCuivre : Palette.texteSourdine)
                .scaleEffect(isActive ? 1.0 : 0.98, anchor: .leading)
            if let translated, !translated.isEmpty {
                Text(translated)
                    .font(Typo.corps)
                    .foregroundStyle(Palette.signalTeal)
            }
        }
        .opacity(isActive ? 1 : 0.55)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.3), value: isActive)
        .padding(.vertical, Spacing.xs)
    }
}
