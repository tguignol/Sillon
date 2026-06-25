import SwiftUI

/// Styles de visualisation de spectre. Seul `circularBars` (cercle de fréquences) est rendu pour
/// l'instant ; les autres sont prévus et un sélecteur sera ajouté plus tard. Les styles non encore
/// implémentés retombent sur `circularBars`.
enum SpectrumStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case circularBars    // cercle de fréquences
    case waveform        // ondulation (à venir)
    case bars            // barres (à venir)
    case cascade         // cascade (à venir)
    case oscilloscope    // oscilloscope (à venir)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .circularBars: "Cercle de fréquences"
        case .waveform: "Ondulation"
        case .bars: "Barres"
        case .cascade: "Cascade"
        case .oscilloscope: "Oscilloscope"
        }
    }
}

/// Spectre audio dessiné en couronne autour de la pochette (remplace l'anneau de progression).
/// `levels` : magnitudes 0…1 par bande de fréquence (graves → aigus).
struct SpectrumRingView: View {
    var levels: [Float]
    var style: SpectrumStyle = .circularBars

    var body: some View {
        Canvas { context, size in
            // Seul le cercle de fréquences est implémenté ; les autres styles s'y rabattent.
            drawCircularBars(context: context, size: size)
        }
        .animation(.easeOut(duration: 0.08), value: levels)
    }

    private func drawCircularBars(context: GraphicsContext, size: CGSize) {
        let count = levels.count
        guard count > 0 else { return }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxBar = min(size.width, size.height) * 0.07
        let baseRadius = min(size.width, size.height) / 2 - maxBar - 1

        // Couronne de fond discrète.
        let baseCircle = Path(ellipseIn: CGRect(
            x: center.x - baseRadius, y: center.y - baseRadius,
            width: baseRadius * 2, height: baseRadius * 2))
        context.stroke(baseCircle, with: .color(Palette.surfaceElevee), lineWidth: 1)

        // Miroir gauche/droite pour une couronne dense et symétrique (graves en haut).
        let positions = count * 2
        for p in 0..<positions {
            let index = p < count ? p : (positions - 1 - p)
            let level = CGFloat(max(0, min(1, levels[index])))
            let barLength = 2 + level * maxBar

            let angle = (Double(p) / Double(positions)) * 2 * .pi - .pi / 2
            let cosA = CGFloat(cos(angle)), sinA = CGFloat(sin(angle))
            let start = CGPoint(x: center.x + cosA * baseRadius, y: center.y + sinA * baseRadius)
            let end = CGPoint(x: center.x + cosA * (baseRadius + barLength), y: center.y + sinA * (baseRadius + barLength))

            var bar = Path()
            bar.move(to: start)
            bar.addLine(to: end)

            // Cuivre qui s'éclaire avec le niveau ; pointe vers le teal sur les pics.
            let color = Palette.accentCuivre.opacity(0.35 + 0.65 * Double(level))
            context.stroke(bar, with: .color(color), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }
    }
}

#Preview {
    SpectrumRingView(levels: (0..<48).map { Float(abs(sin(Double($0) / 3)) * 0.8) })
        .frame(width: 300, height: 300)
        .padding(40)
        .background(Palette.fondNoir)
}
