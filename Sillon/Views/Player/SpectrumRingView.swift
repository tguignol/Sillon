import SwiftUI

/// Styles de visualisation de spectre, tous rendus en couronne autour de la pochette.
enum SpectrumStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case circularBars    // cercle de fréquences
    case bars            // barres
    case waveform        // ondulation
    case cascade         // cascade
    case oscilloscope    // oscilloscope
    case off             // aucun spectre → pochette carrée

    var id: String { rawValue }

    var label: String {
        switch self {
        case .circularBars: "Cercle de fréquences"
        case .bars: "Barres"
        case .waveform: "Ondulation"
        case .cascade: "Cascade"
        case .oscilloscope: "Oscilloscope"
        case .off: "Aucun"
        }
    }

    var systemImage: String {
        switch self {
        case .circularBars: "circle.dotted"
        case .bars: "chart.bar.fill"
        case .waveform: "wave.3.right"
        case .cascade: "square.stack.3d.up.fill"
        case .oscilloscope: "waveform.path.ecg"
        case .off: "circle"
        }
    }
}

/// Spectre audio dessiné en couronne autour de la pochette. `levels` : magnitudes 0…1 par bande
/// (graves → aigus). `waveform` : forme d'onde temporelle -1…1 (style oscilloscope).
struct SpectrumRingView: View {
    var levels: [Float]
    var waveform: [Float] = []
    var style: SpectrumStyle = .circularBars

    @State private var history: [[Float]] = []

    var body: some View {
        Canvas { context, size in
            switch style {
            case .circularBars: drawCircularBars(context, size)
            case .bars: drawBars(context, size)
            case .waveform: drawWaveform(context, size)
            case .cascade: drawCascade(context, size)
            case .oscilloscope: drawOscilloscope(context, size)
            case .off: break   // pas de spectre (la vue n'est de toute façon pas affichée dans ce cas)
            }
        }
        .onChange(of: levels) { _, new in
            // On accumule l'historique en continu (peu coûteux) pour que la cascade soit prête
            // instantanément dès qu'on bascule dessus, au lieu de démarrer vide.
            history.append(new)
            if history.count > 18 { history.removeFirst() }
        }
    }

    // MARK: - Géométrie

    private func polar(_ c: CGPoint, _ r: CGFloat, _ a: CGFloat) -> CGPoint {
        CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
    }

    private func geometry(_ size: CGSize) -> (center: CGPoint, base: CGFloat, maxBar: CGFloat) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxBar = min(size.width, size.height) * 0.07
        let base = min(size.width, size.height) / 2 - maxBar - 1
        return (center, base, maxBar)
    }

    /// Niveaux miroités (gauche/droite) pour une couronne symétrique, graves en haut.
    private func mirrored(_ values: [Float]) -> [Float] {
        values + values.reversed()
    }

    // MARK: - Styles

    private func drawCircularBars(_ context: GraphicsContext, _ size: CGSize) {
        guard !levels.isEmpty else { return }
        let g = geometry(size)
        let values = mirrored(levels)
        for (i, v) in values.enumerated() {
            let level = CGFloat(max(0, min(1, v)))
            let angle = CGFloat(Double(i) / Double(values.count)) * 2 * .pi - .pi / 2
            let start = polar(g.center, g.base, angle)
            let end = polar(g.center, g.base + 2 + level * g.maxBar * 0.85, angle)
            var bar = Path(); bar.move(to: start); bar.addLine(to: end)
            context.stroke(bar, with: .color(Palette.accentCuivre.opacity(0.35 + 0.65 * Double(level))),
                           style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        }
    }

    private func drawBars(_ context: GraphicsContext, _ size: CGSize) {
        guard !levels.isEmpty else { return }
        let g = geometry(size)
        let values = mirrored(levels)
        let count = values.count
        for (i, v) in values.enumerated() {
            let level = CGFloat(max(0, min(1, v)))
            let angle = CGFloat(Double(i) / Double(count)) * 2 * .pi - .pi / 2
            let start = polar(g.center, g.base, angle)
            let end = polar(g.center, g.base + 2 + level * g.maxBar * 0.85, angle)
            var bar = Path(); bar.move(to: start); bar.addLine(to: end)
            // Barres épaisses, pointe teal sur les pics.
            let color = level > 0.7 ? Palette.signalTeal : Palette.accentCuivre
            context.stroke(bar, with: .color(color.opacity(0.4 + 0.6 * Double(level))),
                           style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        }
    }

    private func drawWaveform(_ context: GraphicsContext, _ size: CGSize) {
        guard levels.count > 1 else { return }
        let g = geometry(size)
        let values = mirrored(smoothed(levels))
        let path = closedRadialPath(center: g.center, base: g.base + g.maxBar * 0.15, amplitude: g.maxBar * 0.75, values: values)
        context.stroke(path, with: .color(Palette.accentCuivre.opacity(0.9)), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        context.fill(path, with: .color(Palette.accentCuivre.opacity(0.08)))
    }

    private func drawCascade(_ context: GraphicsContext, _ size: CGSize) {
        guard !history.isEmpty else { drawWaveform(context, size); return }
        let g = geometry(size)
        let frames = history.suffix(18)
        let n = frames.count
        for (age, frame) in frames.enumerated() {
            // Les plus récents à l'extérieur, les anciens vers l'intérieur et estompés.
            let t = CGFloat(age) / CGFloat(max(1, n - 1))   // 0 (ancien) → 1 (récent)
            let radius = g.base - (1 - t) * g.maxBar * 1.6
            let values = mirrored(frame)
            let path = closedRadialPath(center: g.center, base: radius, amplitude: g.maxBar * 0.3, values: values)
            context.stroke(path, with: .color(Palette.signalTeal.opacity(0.12 + 0.5 * Double(t))), lineWidth: 1.0)
        }
    }

    private func drawOscilloscope(_ context: GraphicsContext, _ size: CGSize) {
        guard waveform.count > 2 else { drawCircularBars(context, size); return }
        let g = geometry(size)
        let amplitude = g.maxBar * 0.7
        var path = Path()
        let count = waveform.count
        for i in 0..<count {
            let sample = CGFloat(max(-1, min(1, waveform[i])))
            let angle = CGFloat(Double(i) / Double(count)) * 2 * .pi - .pi / 2
            let r = g.base - g.maxBar * 0.2 + sample * amplitude
            let point = polar(g.center, r, angle)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        context.stroke(path, with: .color(Palette.signalTeal.opacity(0.9)), style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
    }

    // MARK: - Outils de tracé

    private func smoothed(_ v: [Float]) -> [Float] {
        guard v.count > 2 else { return v }
        return v.indices.map { i in
            let a = v[max(0, i - 1)], b = v[i], c = v[min(v.count - 1, i + 1)]
            return (a + b + c) / 3
        }
    }

    private func closedRadialPath(center: CGPoint, base: CGFloat, amplitude: CGFloat, values: [Float]) -> Path {
        var path = Path()
        let count = values.count
        for i in 0...count {
            let v = CGFloat(max(0, min(1, values[i % count])))
            let angle = CGFloat(Double(i) / Double(count)) * 2 * .pi - .pi / 2
            let point = polar(center, base + v * amplitude, angle)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    let demo = (0..<48).map { Float(abs(sin(Double($0) / 3)) * 0.8) }
    return VStack(spacing: 20) {
        ForEach(SpectrumStyle.allCases) { style in
            SpectrumRingView(levels: demo, waveform: (0..<128).map { Float(sin(Double($0) / 5)) }, style: style)
                .frame(width: 120, height: 120)
        }
    }
    .padding()
    .background(Palette.fondNoir)
}
