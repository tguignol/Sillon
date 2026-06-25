import SwiftUI

/// Anneau « sillon » : fine couronne entourant la pochette qui trace la progression de lecture, en
/// écho au sillon d'un vinyle. Élément signature de l'app (cf. Docs/DESIGN_SYSTEM.md).
struct GrooveRingView: View {
    /// Progression 0…1.
    var progress: Double

    var body: some View {
        ZStack {
            // Fins sillons concentriques décoratifs.
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .stroke(Palette.texteSourdine.opacity(0.10), lineWidth: 0.5)
                    .padding(Double(i) * 7)
            }
            // Couronne de fond.
            Circle()
                .stroke(Palette.surfaceElevee, lineWidth: 4)
            // Progression cuivrée.
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(Palette.accentCuivre, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
        }
    }
}

#Preview {
    GrooveRingView(progress: 0.35)
        .frame(width: 280, height: 280)
        .padding(40)
        .background(Palette.fondNoir)
}
