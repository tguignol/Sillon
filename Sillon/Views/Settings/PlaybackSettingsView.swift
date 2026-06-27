import SwiftUI

/// Réglages de lecture « audiophile » : normalisation du volume (ReplayGain). Le fondu enchaîné
/// (crossfade) sera ajouté à cette même vue. Préférences légères persistées en @AppStorage, lues
/// par `PlayerController` au moment de planifier / d'enchaîner les morceaux.
struct PlaybackSettingsView: View {
    @Environment(\.playerController) private var player
    @AppStorage("crossfadeDuration")        private var crossfadeDuration: Double = 0
    @AppStorage("replayGainMode")           private var replayGainModeRaw = ReplayGainMode.off.rawValue
    @AppStorage("replayGainClipProtection") private var clipProtection = true
    @AppStorage("replayGainPreampDB")       private var preampDB: Double = 0

    private var replayGainMode: ReplayGainMode {
        ReplayGainMode(rawValue: replayGainModeRaw) ?? .off
    }
    private var crossfadeLabel: String {
        crossfadeDuration == 0 ? "Sans (gapless)" : String(format: "%.0f s", crossfadeDuration)
    }

    var body: some View {
        Form {
            // MARK: Crossfade
            Section {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack {
                        Text("Durée du fondu")
                        Spacer()
                        Text(crossfadeLabel).techniqueData()
                    }
                    Slider(value: $crossfadeDuration, in: 0...12, step: 1)
                        .tint(Palette.accentCuivre)
                }
                .padding(.vertical, Spacing.xs)
            } header: {
                Text("Crossfade")
            } footer: {
                Text("0 s conserve l'enchaînement sans blanc (gapless). Au-delà, les morceaux se fondent l'un dans l'autre.")
            }

            // MARK: ReplayGain
            Section {
                Picker("Normalisation", selection: $replayGainModeRaw) {
                    ForEach(ReplayGainMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.systemImage).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(Palette.accentCuivre)

                Toggle("Protection anti-saturation", isOn: $clipProtection)
                    .tint(Palette.signalTeal)
                    .disabled(replayGainMode == .off)

                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack {
                        Text("Pré-amplification")
                        Spacer()
                        Text(String(format: "%+.0f dB", preampDB))
                            .techniqueData()
                    }
                    Slider(value: $preampDB, in: -6...6, step: 1)
                        .tint(Palette.accentCuivre)
                }
                .padding(.vertical, Spacing.xs)
                .disabled(replayGainMode == .off)
                .opacity(replayGainMode == .off ? 0.4 : 1)
            } header: {
                Text("ReplayGain")
            } footer: {
                Text("Égalise le volume perçu d'une piste à l'autre (mode Piste) ou conserve la dynamique d'un album (mode Album). Le limiteur anti-saturation évite l'écrêtage quand le gain est positif.")
            }
        }
        .scrollContentBackground(.hidden)   // laisse voir Palette.fondNoir derrière le Form groupé
        .background(Palette.fondNoir)
        .navigationTitle(LanguageManager.string("Lecture"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // Retour audio instantané sur le morceau en cours, sans attendre la prochaine transition.
        .onChange(of: crossfadeDuration) { player?.refreshCrossfade() }
        .onChange(of: replayGainModeRaw) { player?.refreshReplayGain() }
        .onChange(of: clipProtection)    { player?.refreshReplayGain() }
        .onChange(of: preampDB)          { player?.refreshReplayGain() }
    }
}

#Preview {
    NavigationStack { PlaybackSettingsView() }
}
