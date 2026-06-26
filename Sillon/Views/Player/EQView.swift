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
    @State private var selectedBand: Int?
    @Query(sort: \EQPreset.slot) private var allPresets: [EQPreset]

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
        .task {
            EQPresetStore.ensure(context)    // crée les 4 presets par défaut de chaque mode
            let loaded = EQSettingsStore.load(context)
            ensureParametricArrays(loaded)   // les deux modes éditent fréquences/largeurs
            settings = loaded
        }
    }

    private func content(settings: EQSettings) -> some View {
        VStack(spacing: Spacing.l) {
            Toggle("Égaliseur activé", isOn: Binding(
                get: { settings.isEnabled },
                set: { settings.isEnabled = $0; commit(settings) }
            ))
            .tint(Palette.signalTeal)
            .padding(.horizontal, Spacing.l)

            Picker("Mode", selection: Binding(
                get: { settings.mode },
                set: { setMode($0, settings: settings) }
            )) {
                ForEach(EQMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.l)

            Stepper("Bandes : \(settings.bandCount)", value: Binding(
                get: { settings.bandCount },
                set: { setBandCount($0, settings: settings) }
            ), in: 6...12)
            .padding(.horizontal, Spacing.l)

            Group {
                switch settings.mode {
                case .normal: normalEditor(settings)
                case .parametric: parametricEditor(settings)
                case .graphic: graphicEditor(settings)
                }
            }
            .frame(maxHeight: .infinity)
            .opacity(settings.isEnabled ? 1 : 0.4)
            .disabled(!settings.isEnabled)

            presetsSection(settings)

            Button("Réinitialiser (plat)") { resetFlat(settings) }
                .buttonStyle(.bordered)
                .tint(Palette.accentCuivre)
        }
        .padding(.top, Spacing.l)
    }

    // MARK: - Mode « Normal » (curseurs verticaux, fréquences fixes)

    private func normalEditor(_ settings: EQSettings) -> some View {
        HStack(alignment: .center, spacing: Spacing.s) {
            ForEach(settings.gainsDB.indices, id: \.self) { index in
                bandSlider(settings: settings, index: index)
            }
        }
        .frame(height: 240)
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

    // MARK: - Mode « Graphique » (courbe à déplacer à la main)

    private func graphicEditor(_ settings: EQSettings) -> some View {
        VStack(spacing: Spacing.m) {
            EQCurveView(settings: settings, selectedBand: $selectedBand, onChange: { commit(settings) })
                .padding(.horizontal, Spacing.l)

            if let i = selectedBand, settings.gainsDB.indices.contains(i) {
                selectedBandControls(settings, i)
            } else {
                Text("Glissez les poignées (fréquence ↔, gain ↕). Touchez-en une pour régler sa largeur.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.l)
            }
        }
    }

    private func selectedBandControls(_ settings: EQSettings, _ index: Int) -> some View {
        let freq = parametricFrequency(settings, index)
        let bw = parametricBandwidth(settings, index)
        return VStack(spacing: Spacing.xs) {
            Text("Bande \(index + 1) · \(EQBands.label(for: Float(freq))) Hz · \(String(format: "%+.0f", settings.gainsDB[index])) dB · \(String(format: "%.1f", bw)) oct")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Palette.signalTeal)
            labeledSlider(
                "Largeur",
                value: Binding(get: { bw }, set: { setBandwidth($0, settings: settings, index: index) }),
                range: 0.1...3.0
            )
            .padding(.horizontal, Spacing.l)
        }
    }

    // MARK: - Mode « Paramétrique »

    private func parametricEditor(_ settings: EQSettings) -> some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                ForEach(settings.gainsDB.indices, id: \.self) { index in
                    parametricBand(settings: settings, index: index)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
        }
    }

    private func parametricBand(settings: EQSettings, index: Int) -> some View {
        let freq = parametricFrequency(settings, index)
        let bw = parametricBandwidth(settings, index)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("Bande \(index + 1)")
                    .font(.subheadline).foregroundStyle(Palette.texteIvoire)
                Spacer()
                Text("\(EQBands.label(for: Float(freq))) Hz · \(String(format: "%+.0f", settings.gainsDB[index])) dB · \(String(format: "%.1f", bw)) oct")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Palette.signalTeal)
            }
            labeledSlider(
                "Gain",
                value: Binding(get: { settings.gainsDB[index] },
                               set: { settings.gainsDB[index] = $0; commit(settings) }),
                range: Double(EQBands.minGainDB)...Double(EQBands.maxGainDB)
            )
            // Fréquence sur échelle logarithmique (20 Hz … 20 kHz).
            labeledSlider(
                "Fréq.",
                value: Binding(get: { log10(freq) },
                               set: { setFrequency(pow(10, $0), settings: settings, index: index) }),
                range: log10(20.0)...log10(20_000.0)
            )
            labeledSlider(
                "Largeur",
                value: Binding(get: { bw },
                               set: { setBandwidth($0, settings: settings, index: index) }),
                range: 0.1...3.0
            )
        }
        .padding(Spacing.m)
        .background(Palette.surfaceElevee, in: RoundedRectangle(cornerRadius: Spacing.cardCorner, style: .continuous))
    }

    private func labeledSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: Spacing.s) {
            Text(label)
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Slider(value: value, in: range).tint(Palette.accentCuivre)
        }
    }

    private func parametricFrequency(_ settings: EQSettings, _ index: Int) -> Double {
        if settings.frequencies.indices.contains(index) { return settings.frequencies[index] }
        let defaults = EQBands.frequencies(count: settings.bandCount)
        return index < defaults.count ? Double(defaults[index]) : 1000
    }

    private func parametricBandwidth(_ settings: EQSettings, _ index: Int) -> Double {
        settings.bandwidths.indices.contains(index) ? settings.bandwidths[index] : 1.0
    }

    private func setFrequency(_ value: Double, settings: EQSettings, index: Int) {
        ensureParametricArrays(settings)
        guard settings.frequencies.indices.contains(index) else { return }
        settings.frequencies[index] = min(20_000, max(20, value))
        commit(settings)
    }

    private func setBandwidth(_ value: Double, settings: EQSettings, index: Int) {
        ensureParametricArrays(settings)
        guard settings.bandwidths.indices.contains(index) else { return }
        settings.bandwidths[index] = min(5.0, max(0.05, value))
        commit(settings)
    }

    private func setMode(_ mode: EQMode, settings: EQSettings) {
        settings.mode = mode
        if mode == .normal {
            // Bandes standard : fréquences log fixes + largeur 1 octave (gains conservés). Ainsi
            // l'affichage = le son, et la transposition vers Paramétrique/Graphique reste exacte.
            settings.frequencies = EQBands.frequencies(count: settings.bandCount).map(Double.init)
            settings.bandwidths = Array(repeating: 1.0, count: settings.bandCount)
        } else {
            ensureParametricArrays(settings)
        }
        selectedBand = nil
        commit(settings)
    }

    /// Garantit que `frequencies`/`bandwidths` ont la taille `bandCount` (remplies aux défauts si besoin).
    private func ensureParametricArrays(_ settings: EQSettings) {
        let count = settings.bandCount
        if settings.frequencies.count != count {
            settings.frequencies = EQBands.frequencies(count: count).map(Double.init)
        }
        if settings.bandwidths.count != count {
            settings.bandwidths = Array(repeating: 1.0, count: count)
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
        // Les fréquences log dépendent du nombre de bandes → on réamorce fréquences/largeurs aux défauts.
        settings.frequencies = EQBands.frequencies(count: count).map(Double.init)
        settings.bandwidths = Array(repeating: 1.0, count: count)
        commit(settings)
    }

    /// Remet TOUT à plat (gains 0, fréquences aux défauts log, largeurs 1 octave). Comme les deux
    /// modes partagent ces tableaux, l'aplatissement vaut pour le Graphique ET le Paramétrique.
    private func resetFlat(_ settings: EQSettings) {
        settings.gainsDB = Array(repeating: 0, count: settings.bandCount)
        settings.frequencies = EQBands.frequencies(count: settings.bandCount).map(Double.init)
        settings.bandwidths = Array(repeating: 1.0, count: settings.bandCount)
        commit(settings)
    }

    private func commit(_ settings: EQSettings) {
        settings.updatedAt = .now
        try? context.save()
        player?.refreshEQ()
    }

    // MARK: - Presets

    private func presetsSection(_ settings: EQSettings) -> some View {
        let presets = allPresets.filter { $0.modeRaw == settings.mode.rawValue }
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Presets — \(settings.mode.label)")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(presets) { preset in
                HStack(spacing: Spacing.s) {
                    TextField("Réglage \(preset.slot)", text: Binding(
                        get: { preset.name },
                        set: { preset.name = $0; try? context.save() }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)

                    // Enregistrer les réglages courants dans ce preset.
                    Button { savePreset(preset, from: settings) } label: {
                        Image(systemName: "tray.and.arrow.down.fill").font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .tint(Palette.accentCuivre)

                    // Appliquer ce preset à l'égaliseur.
                    Button { loadPreset(preset, into: settings) } label: {
                        Image(systemName: "checkmark.circle.fill").font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .tint(Palette.signalTeal)
                }
            }
        }
        .padding(.horizontal, Spacing.l)
    }

    /// Applique un preset aux réglages courants (et reconstruit l'EQ si le nb de bandes change).
    private func loadPreset(_ preset: EQPreset, into settings: EQSettings) {
        settings.mode = preset.mode
        settings.bandCount = preset.bandCount
        settings.gainsDB = preset.gainsDB
        settings.frequencies = preset.frequencies
        settings.bandwidths = preset.bandwidths
        ensureParametricArrays(settings)
        selectedBand = nil
        commit(settings)
    }

    /// Enregistre les réglages courants dans un preset.
    private func savePreset(_ preset: EQPreset, from settings: EQSettings) {
        preset.bandCount = settings.bandCount
        preset.gainsDB = settings.gainsDB
        preset.frequencies = settings.frequencies
        preset.bandwidths = settings.bandwidths
        preset.updatedAt = .now
        try? context.save()
    }
}

#Preview {
    EQView()
        .modelContainer(SillonSchema.makeContainer(inMemory: true))
}
