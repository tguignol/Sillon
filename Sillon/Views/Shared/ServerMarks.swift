import SwiftUI

/// Marques (logos) des serveurs, dessinées vectoriellement pour les pastilles de provenance.
/// Reproduites en SwiftUI plutôt qu'en assets : dégradé garanti, net à toute taille, sans pipeline
/// d'images. Utilisées par `SourceBadge`.

// MARK: - Jellyfin

/// Logo Jellyfin : triangle arrondi creux + petit triangle plein au centre, dégradé violet → bleu.
struct JellyfinMark: View {
    /// Dégradé officiel Jellyfin (#AA5CC3 violet en haut-gauche → #00A4DC bleu en bas-droite).
    private static let gradient = LinearGradient(
        colors: [Color(red: 0.667, green: 0.361, blue: 0.765),
                 Color(red: 0.0, green: 0.643, blue: 0.863)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        Self.gradient
            .mask { JellyfinMarkShape().fill(style: FillStyle(eoFill: true)) }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

/// Forme du logo Jellyfin en espace de conception 48×48 : trois triangles arrondis concentriques
/// (extérieur, trou, triangle plein) réunis dans un seul tracé. Avec un remplissage *even-odd*, le
/// trou entre l'extérieur et l'intérieur reste vide tandis que le triangle central se remplit.
struct JellyfinMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let s = min(rect.width, rect.height) / 48
        // Sommets de base (triangle pointe en haut) et centroïde, en espace 48×48.
        let base = [CGPoint(x: 24, y: 4), CGPoint(x: 5, y: 38), CGPoint(x: 43, y: 38)]
        let g = CGPoint(x: 24, y: 26.67)

        func triangle(scale: CGFloat, trim: CGFloat) {
            let v = base.map { pt -> CGPoint in
                CGPoint(x: rect.minX + (g.x + (pt.x - g.x) * scale) * s,
                        y: rect.minY + (g.y + (pt.y - g.y) * scale) * s)
            }
            addRoundedTriangle(v[0], v[1], v[2], trim: trim * s, to: &p)
        }

        triangle(scale: 1.00, trim: 12.0) // contour extérieur
        triangle(scale: 0.60, trim: 7.2)  // trou
        triangle(scale: 0.34, trim: 4.1)  // triangle plein central
        return p
    }
}

/// Ajoute au tracé un triangle (a, b, c) aux coins arrondis : on rogne chaque arête de `trim` autour
/// du sommet, puis on relie par une courbe quadratique dont le point de contrôle est le sommet.
private func addRoundedTriangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, trim d: CGFloat, to p: inout Path) {
    func unit(_ from: CGPoint, _ to: CGPoint) -> CGPoint {
        let dx = to.x - from.x, dy = to.y - from.y
        let len = max((dx * dx + dy * dy).squareRoot(), 0.0001)
        return CGPoint(x: dx / len, y: dy / len)
    }
    func along(_ from: CGPoint, _ u: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: from.x + u.x * t, y: from.y + u.y * t)
    }
    let uAB = unit(a, b), uBC = unit(b, c), uCA = unit(c, a)
    let aOut = along(a, uAB, d)   // sur AB, près de A
    let bIn  = along(b, uAB, -d)  // sur AB, près de B
    let bOut = along(b, uBC, d)   // sur BC, près de B
    let cIn  = along(c, uBC, -d)  // sur BC, près de C
    let cOut = along(c, uCA, d)   // sur CA, près de C
    let aIn  = along(a, uCA, -d)  // sur CA, près de A

    p.move(to: aOut)
    p.addLine(to: bIn)
    p.addQuadCurve(to: bOut, control: b)
    p.addLine(to: cIn)
    p.addQuadCurve(to: cOut, control: c)
    p.addLine(to: aIn)
    p.addQuadCurve(to: aOut, control: a)
    p.closeSubpath()
}

// MARK: - Navidrome / Subsonic

/// Logo Navidrome : disque vinyle bleu cerné de noir, sillons en arcs (haut-gauche / bas-droite),
/// étiquette blanche centrale et trou central.
struct NavidromeMark: View {
    private static let blue = Color(red: 0.12, green: 0.55, blue: 1.0)

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().fill(Self.blue)
                VinylGrooves()
                    .stroke(Color.black.opacity(0.85),
                            style: StrokeStyle(lineWidth: side * 0.06, lineCap: .round))
                Circle().fill(.white).frame(width: side * 0.34, height: side * 0.34)
                Circle().fill(.black).frame(width: side * 0.07, height: side * 0.07)
            }
            .overlay(Circle().strokeBorder(.black, lineWidth: side * 0.085))
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Sillons du vinyle : deux arcs concentriques en haut-gauche et deux en bas-droite (motif diagonal
/// classique d'une icône de disque).
struct VinylGrooves: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for factor in [0.74, 0.56] {
            let rr = radius * factor
            // Chaque arc démarre son PROPRE sous-tracé (move(to:) avant addArc). Sinon `addArc` relie
            // le point courant au début de l'arc par une ligne droite, qui barrerait le disque.
            // Haut-gauche : de 180° (gauche, point de départ c-rr) à 270° (haut).
            p.move(to: CGPoint(x: c.x - rr, y: c.y))
            p.addArc(center: c, radius: rr, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            // Bas-droite : de 0° (droite, point de départ c+rr) à 90° (bas).
            p.move(to: CGPoint(x: c.x + rr, y: c.y))
            p.addArc(center: c, radius: rr, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        }
        return p
    }
}

#Preview("Marques serveurs") {
    HStack(spacing: 24) {
        JellyfinMark().frame(width: 80, height: 80)
        NavidromeMark().frame(width: 80, height: 80)
    }
    .padding()
}
