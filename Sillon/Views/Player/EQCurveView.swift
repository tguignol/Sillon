import SwiftUI

/// Éditeur graphique de l'égaliseur en « courbe de réponse » (inspiré de Sennheiser Smart Control) :
/// une poignée par bande, déplacée à la main — horizontale = fréquence (échelle log), verticale = gain.
/// La courbe lissée est la somme des cloches paramétriques (la largeur de chaque bande modèle sa cloche).
/// Toucher une poignée la sélectionne (sa largeur se règle alors via un curseur dédié dans l'écran EQ).
struct EQCurveView: View {
    let settings: EQSettings
    @Binding var selectedBand: Int?
    let onChange: () -> Void

    private let minGain = Double(EQBands.minGainDB)
    private let maxGain = Double(EQBands.maxGainDB)
    private let minFreq = 20.0
    private let maxFreq = 20_000.0

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Canvas { ctx, _ in
                    drawGrid(ctx, size)
                    drawCurve(ctx, size)
                }
                ForEach(settings.gainsDB.indices, id: \.self) { i in
                    handle(i, size: size)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { selectedBand = nil }
        }
        .frame(height: 220)
        .background(Palette.surfaceElevee, in: RoundedRectangle(cornerRadius: Spacing.cardCorner, style: .continuous))
    }

    // MARK: - Poignées

    @ViewBuilder
    private func handle(_ i: Int, size: CGSize) -> some View {
        let isSelected = selectedBand == i
        Circle()
            .fill(isSelected ? Palette.signalTeal : Palette.accentCuivre)
            .overlay(Circle().stroke(Palette.fondNoir.opacity(0.6), lineWidth: 2))
            .frame(width: isSelected ? 24 : 17, height: isSelected ? 24 : 17)
            .position(point(forBand: i, size: size))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        selectedBand = i
                        ensureArrays()
                        let f = freq(forX: value.location.x, width: size.width)
                        let g = gain(forY: value.location.y, height: size.height)
                        settings.frequencies[i] = min(maxFreq, max(minFreq, f))
                        settings.gainsDB[i] = min(maxGain, max(minGain, g))
                        onChange()
                    }
            )
    }

    // MARK: - Conversions (fréquence/gain ↔ point écran)

    private func bandFreq(_ i: Int) -> Double {
        if settings.frequencies.indices.contains(i) { return settings.frequencies[i] }
        let defaults = EQBands.frequencies(count: settings.bandCount)
        return i < defaults.count ? Double(defaults[i]) : 1000
    }

    private func point(forBand i: Int, size: CGSize) -> CGPoint {
        CGPoint(x: x(forFreq: bandFreq(i), width: size.width),
                y: y(forGain: settings.gainsDB[i], height: size.height))
    }

    private func x(forFreq f: Double, width: CGFloat) -> CGFloat {
        let t = (log10(f) - log10(minFreq)) / (log10(maxFreq) - log10(minFreq))
        return CGFloat(t) * width
    }
    private func freq(forX x: CGFloat, width: CGFloat) -> Double {
        let t = max(0, min(1, Double(x / max(1, width))))
        return pow(10, log10(minFreq) + t * (log10(maxFreq) - log10(minFreq)))
    }
    private func y(forGain g: Double, height: CGFloat) -> CGFloat {
        let t = (g - minGain) / (maxGain - minGain)
        return CGFloat(1 - t) * height
    }
    private func gain(forY y: CGFloat, height: CGFloat) -> Double {
        let t = max(0, min(1, Double(1 - y / max(1, height))))
        return minGain + t * (maxGain - minGain)
    }

    // MARK: - Tracé

    /// Réponse approchée (dB) à une fréquence : somme de cloches gaussiennes en log-fréquence,
    /// la largeur (octaves) de chaque bande pilotant l'étalement de sa cloche.
    private func responseGain(at f: Double) -> Double {
        var sum = 0.0
        for i in settings.gainsDB.indices {
            let fc = bandFreq(i)
            let g = settings.gainsDB[i]
            let bw = settings.bandwidths.indices.contains(i) ? settings.bandwidths[i] : 1.0
            let d = (log2(f) - log2(fc)) / max(0.2, bw)
            sum += g * exp(-0.5 * d * d)
        }
        return sum
    }

    private func drawGrid(_ ctx: GraphicsContext, _ size: CGSize) {
        let y0 = y(forGain: 0, height: size.height)
        var zero = Path()
        zero.move(to: CGPoint(x: 0, y: y0))
        zero.addLine(to: CGPoint(x: size.width, y: y0))
        ctx.stroke(zero, with: .color(Palette.texteSourdine.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

        for f in [100.0, 1000.0, 10_000.0] {
            let gx = x(forFreq: f, width: size.width)
            var line = Path()
            line.move(to: CGPoint(x: gx, y: 0))
            line.addLine(to: CGPoint(x: gx, y: size.height))
            ctx.stroke(line, with: .color(Palette.texteSourdine.opacity(0.15)), lineWidth: 1)
        }
    }

    private func drawCurve(_ ctx: GraphicsContext, _ size: CGSize) {
        var path = Path()
        let steps = 120
        for s in 0...steps {
            let px = CGFloat(s) / CGFloat(steps) * size.width
            let f = freq(forX: px, width: size.width)
            let g = min(maxGain, max(minGain, responseGain(at: f)))
            let py = y(forGain: g, height: size.height)
            if s == 0 { path.move(to: CGPoint(x: px, y: py)) } else { path.addLine(to: CGPoint(x: px, y: py)) }
        }
        var fill = path
        fill.addLine(to: CGPoint(x: size.width, y: size.height))
        fill.addLine(to: CGPoint(x: 0, y: size.height))
        fill.closeSubpath()
        ctx.fill(fill, with: .linearGradient(
            Gradient(colors: [Palette.accentCuivre.opacity(0.18), .clear]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
        ctx.stroke(path, with: .color(Palette.accentCuivre), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
    }

    private func ensureArrays() {
        let count = settings.bandCount
        if settings.frequencies.count != count {
            settings.frequencies = EQBands.frequencies(count: count).map(Double.init)
        }
        if settings.bandwidths.count != count {
            settings.bandwidths = Array(repeating: 1.0, count: count)
        }
    }
}
