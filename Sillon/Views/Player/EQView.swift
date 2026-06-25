import SwiftUI
import SwiftData

/// Écran réglages de l'égaliseur : 6 à 12 bandes à sliders libres (-12…+12 dB), activation, et
/// sauvegarde du dernier état (singleton `EQSettings`). Les changements s'appliquent en direct au
/// moteur de lecture.
struct EQView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.playerController) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var settings: EQSettings?

    var body: some View {
        NavigationStack {
            Group {
                if let settings {
                    content(settings: settings)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Égaliseur")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .background(Palette.fondNoir)
        }
        .task { settings = EQSettingsStore.load(context) }
    }

    private func content(settings: EQSettings) -> some View {
        VStack(spacing: Spacing.xl) {
            Toggle("Égaliseur activé", isOn: Binding(
                get: { settings.isEnabled },
                set: { settings.isEnabled = $0; commit(settings) }
            ))
            .tint(Palette.signalTeal)
            .padding(.horizontal, Spacing.l)

            HStack(alignment: .center, spacing: Spacing.s) {
                ForEach(settings.gainsDB.indices, id: \.self) { index in
                    bandSlider(settings: settings, index: index)
                }
            }
            .frame(height: 240)
            .opacity(settings.isEnabled ? 1 : 0.4)
            .disabled(!settings.isEnabled)

            Stepper("Bandes : \(settings.bandCount)", value: Binding(
                get: { settings.bandCount },
                set: { setBandCount($0, settings: settings) }
            ), in: 6...12)
            .padding(.horizontal, Spacing.l)

            Button("Réinitialiser (plat)") { resetFlat(settings) }
                .buttonStyle(.bordered)
                .tint(Palette.accentCuivre)

            Spacer()
        }
        .padding(.top, Spacing.l)
    }

    private func bandSlider(settings: EQSettings, index: Int) -> some View {
        let frequencies = EQBands.frequencies(count: settings.bandCount)
        return VStack(spacing: Spacing.xs) {
            Text(String(format: "%+.0f", settings.gainsDB[index]))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Palette.signalTeal)
            Slider(
                value: Binding(
                    get: { settings.gainsDB[index] },
                    set: { settings.gainsDB[index] = $0; commit(settings) }
                ),
                in: Double(EQBands.minGainDB)...Double(EQBands.maxGainDB)
            )
            .tint(Palette.accentCuivre)
            .rotationEffect(.degrees(-90))
            .frame(width: 180)
            .frame(width: 30, height: 180)
            Text(EQBands.label(for: index < frequencies.count ? frequencies[index] : 0))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func setBandCount(_ count: Int, settings: EQSettings) {
        guard count != settings.bandCount else { return }
        var gains = settings.gainsDB
        if count > gains.count {
            gains.append(contentsOf: Array(repeating: 0, count: count - gains.count))
        } else {
            gains = Array(gains.prefix(count))
        }
        settings.bandCount = count
        settings.gainsDB = gains
        commit(settings)
    }

    private func resetFlat(_ settings: EQSettings) {
        settings.gainsDB = Array(repeating: 0, count: settings.bandCount)
        commit(settings)
    }

    private func commit(_ settings: EQSettings) {
        settings.updatedAt = .now
        try? context.save()
        player?.refreshEQ()
    }
}

#Preview {
    EQView()
        .modelContainer(SillonSchema.makeContainer(inMemory: true))
}
