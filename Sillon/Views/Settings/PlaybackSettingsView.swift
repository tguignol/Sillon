import SwiftUI

/// Réglages de lecture « audiophile » : normalisation du volume (ReplayGain). Le fondu enchaîné
/// (crossfade) sera ajouté à cette même vue. Préférences légères persistées en @AppStorage, lues
/// par `PlayerController` au moment de planifier / d'enchaîner les morceaux.
struct PlaybackSettingsView: View {
    @Environment(\.playerController) private var player
    @AppStorage("replayGainMode")           private var replayGainModeRaw = ReplayGainMode.off.rawValue
    @AppStorage("replayGainClipProtection") private var clipProtection = true
    @AppStorage("replayGainPreampDB")       private var preampDB: Double = 0

    private var replayGainMode: ReplayGainMode {
        ReplayGainMode(rawValue: replayGainModeRaw) ?? .off
    }

    var body: some View {
        Form {
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
        .navigationTitle("Lecture")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // Retour audio instantané sur le morceau en cours, sans attendre la prochaine transition.
        .onChange(of: replayGainModeRaw) { player?.refreshReplayGain() }
        .onChange(of: clipProtection)    { player?.refreshReplayGain() }
        .onChange(of: preampDB)          { player?.refreshReplayGain() }
    }
}

#Preview {
    NavigationStack { PlaybackSettingsView() }
}
