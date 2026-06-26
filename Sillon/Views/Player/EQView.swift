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
    @State private var showPresets = false
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

            ZStack {
                Group {
                    switch settings.mode {
                    case .normal: normalEditor(settings)
                    case .parametric: parametricEditor(settings)
                    case .graphic: graphicEditor(settings)
                    }
                }
                .opacity(settings.isEnabled ? 1 : 0.4)
                .disabled(!settings.isEnabled)

                // Les presets se superposent à l'éditeur quand on les ouvre (le bouton reste visible dessous).
                if showPresets {
                    presetsPanel(settings).transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity)

            presetsToggleButton

            Button("Réinitialiser (plat)") { resetFlat(settings) }
                .buttonStyle(.bordered)
                .tint(Palette.accentCuivre)
        }
        .padding(.top, Spacing.l)
    }

    // MARK: - Mode « Normal » (curseurs verticaux, fréquences fixes)

    private func normalEditor(_ settings: EQSettings) -> some View {
        let count = max(1, settings.bandCount)
        // Espacement large pour peu de bandes, qui se resserre à mesure qu'on en ajoute.
        let spacing = max(CGFloat(2), CGFloat(30 - count * 2))
        // Largeur de colonne (barre) élargie pour peu de bandes, plus fine quand on en ajoute.
        let barWidth = min(CGFloat(46), max(CGFloat(14), 360 / CGFloat(count)))
        return HStack(alignment: .center, spacing: spacing) {
            ForEach(settings.gainsDB.indices, id: \.self) { index in
                bandSlider(settings: settings, index: index, barWidth: barWidth)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 240)
        .padding(.horizontal, Spacing.l)
    }

    private func bandSlider(settings: EQSettings, index: Int, barWidth: CGFloat) -> some View {
        let frequencies = EQBands.frequencies(count: settings.bandCount)
        return VStack(spacing: Spacing.xs) {
            Text(String(format: "%+.0f", settings.gainsDB[index]))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Palette.signalTeal)
            VerticalGainFader(
                value: Binding(get: { settings.gainsDB[index] },
                               set: { settings.gainsDB[index] = $0 }),
                range: Double(EQBands.minGainDB)...Double(EQBands.maxGainDB),
                onChange: { commit(settings) }
            )
            .frame(width: barWidth)
            .frame(maxHeight: .infinity)
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

    /// Bouton d'ouverture des presets : change de couleur quand actif, reste toujours visible.
    private var presetsToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showPresets.toggle() }
        } label: {
            Label(showPresets ? "Fermer les presets" : "Presets", systemImage: "rectangle.stack.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.s)
                .background(showPresets ? Palette.accentCuivre : Palette.surfaceElevee, in: Capsule())
                .foregroundStyle(showPresets ? Palette.fondNoir : Palette.texteIvoire)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.l)
    }

    /// Panneau presets superposé à l'éditeur (fond opaque pour le couvrir).
    private func presetsPanel(_ settings: EQSettings) -> some View {
        ScrollView {
            presetsSection(settings).padding(.top, Spacing.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.fondNoir)
    }

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

/// Curseur vertical (« fader ») d'une bande de l'égaliseur Normal : barre large, remplie depuis le
/// 0 dB jusqu'au niveau courant ; un glissement vertical règle le gain.
private struct VerticalGainFader: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onChange: () -> Void

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let span = range.upperBound - range.lowerBound
            let frac = span > 0 ? (value - range.lowerBound) / span : 0.5
            let zeroFrac = span > 0 ? (0 - range.lowerBound) / span : 0.5
            let thumbY = (1 - frac) * h
            let zeroY = (1 - zeroFrac) * h
            ZStack(alignment: .topLeading) {
                Capsule().fill(Palette.surfaceElevee)
                Capsule().fill(Palette.accentCuivre.opacity(0.9))
                    .frame(height: max(2, abs(thumbY - zeroY)))
                    .offset(y: min(thumbY, zeroY))
                Capsule().fill(Palette.texteIvoire)
                    .frame(height: 6)
                    .offset(y: thumbY - 3)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { v in
                    let f = 1 - max(0, min(1, v.location.y / max(1, h)))
                    value = range.lowerBound + f * span
                    onChange()
                }
            )
        }
    }
}

#Preview {
    EQView()
        .modelContainer(SillonSchema.makeContainer(inMemory: true))
}
