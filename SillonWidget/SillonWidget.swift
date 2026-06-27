//
//  SillonWidget.swift
//  SillonWidget
//
//  Widget « Lecture en cours » de Sillon — formats medium (pleine largeur, demi-hauteur) et grand.
//  Phase 1 (cette version) : disposition fidèle aux maquettes, alimentée par des DONNÉES D'EXEMPLE.
//  Phase 2 (à venir) : vraies données via App Group + boutons interactifs (`AudioPlaybackIntent`).
//

import WidgetKit
import SwiftUI
import UIKit

// MARK: - Palette locale

// Le widget est une cible séparée de l'app : on redéfinit ici les mêmes teintes (variantes clair/sombre
// identiques à `Palette` côté app). À mutualiser plus tard si on partage le fichier de thème.
private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

private enum WPalette {
    static let fond = Color(light: 0xF6F4EF, dark: 0x0B0D0F)
    static let cuivre = Color(light: 0xB06D2C, dark: 0xD98E4A)
    static let teal = Color(light: 0x2E7D75, dark: 0x4FA8A0)
    static let texte = Color(light: 0x1C1A17, dark: 0xF3F1EC)
    static let sourdine = Color(light: 0x6E6A64, dark: 0x9A9590)
    static let piste = Color(light: 0xDCD7CC, dark: 0x2C2F33)
    static let pochette = Color(light: 0xC2A98A, dark: 0x4A4036)
}

private func mmss(_ seconds: Double) -> String {
    let t = max(0, Int(seconds.rounded()))
    return "\(t / 60):" + String(format: "%02d", t % 60)
}

// MARK: - Donnée affichée

/// Instantané de lecture rendu par le widget. Données d'exemple en phase 1 ; lues depuis le conteneur
/// partagé (App Group) alimenté par l'app en phase 2.
struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let album: String
    let elapsed: Double
    let duration: Double
    let quality: String
    let isPlaying: Bool
    let isFavorite: Bool

    var fraction: Double { duration > 0 ? min(1, elapsed / duration) : 0 }

    static let sample = NowPlayingEntry(
        date: .now, title: "Come Back and Stay", artist: "Paul Young",
        album: "From Time to Time", elapsed: 21, duration: 264,
        quality: "FLAC · 44,1 kHz", isPlaying: false, isFavorite: true
    )
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry { .sample }
    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) { completion(.sample) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        // Phase 1 : une seule entrée d'exemple. Phase 2 : lecture App Group + reload piloté par l'app.
        completion(Timeline(entries: [.sample], policy: .never))
    }
}

// MARK: - Sous-vues

/// Pochette entourée du spectre. Dans un widget le spectre est forcément statique (rendu décoratif).
private struct CoverSpectrum: View {
    var size: CGFloat
    var body: some View {
        ZStack {
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let base = min(sz.width, sz.height) / 2
                let n = 44
                for i in 0..<n {
                    let lvl = abs(sin(Double(i) * 0.7)) * abs(cos(Double(i) * 0.31))
                    let a = Double(i) / Double(n) * 2 * .pi - .pi / 2
                    let r1 = base * 0.80
                    let r2 = r1 + base * 0.17 * (0.4 + 0.6 * lvl)
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + cos(a) * r1, y: c.y + sin(a) * r1))
                    p.addLine(to: CGPoint(x: c.x + cos(a) * r2, y: c.y + sin(a) * r2))
                    ctx.stroke(p, with: .color(WPalette.cuivre.opacity(0.3 + 0.6 * lvl)),
                               style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                }
            }
            // Pochette « vinyle » (placeholder ; image réelle de l'album en phase 2).
            Circle().fill(WPalette.pochette)
                .overlay(Circle().fill(WPalette.pochette.opacity(0.55)).frame(width: size * 0.2, height: size * 0.2))
                .overlay(Circle().fill(WPalette.fond).frame(width: size * 0.045, height: size * 0.045))
                .padding(size * 0.15)
        }
        .frame(width: size, height: size)
    }
}

private struct ProgressLine: View {
    var fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(WPalette.piste)
                Capsule().fill(WPalette.cuivre).frame(width: max(6, geo.size.width * fraction))
            }
        }
        .frame(height: 4)
    }
}

private struct TransportTrio: View {
    var isPlaying: Bool
    var circle: CGFloat
    var iconSize: CGFloat
    var spacing: CGFloat
    var body: some View {
        HStack(spacing: spacing) {
            Image(systemName: "backward.end.fill").foregroundStyle(WPalette.texte)
            ZStack {
                Circle().fill(WPalette.texte).frame(width: circle, height: circle)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: circle * 0.4)).foregroundStyle(WPalette.fond)
            }
            Image(systemName: "forward.end.fill").foregroundStyle(WPalette.texte)
        }
        .font(.system(size: iconSize))
    }
}

// MARK: - Format medium (pleine largeur, demi-hauteur)

private struct MediumView: View {
    let entry: NowPlayingEntry
    var body: some View {
        HStack(spacing: 14) {
            CoverSpectrum(size: 104)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.title).font(.system(size: 16, design: .serif)).foregroundStyle(WPalette.texte).lineLimit(1)
                Text(entry.artist).font(.system(size: 12, weight: .medium)).foregroundStyle(WPalette.sourdine).lineLimit(1)
                ProgressLine(fraction: entry.fraction).padding(.top, 10)
                HStack {
                    Text(mmss(entry.elapsed)).foregroundStyle(WPalette.sourdine)
                    Spacer()
                    Text(entry.quality).foregroundStyle(WPalette.teal)
                    Spacer()
                    Text(mmss(entry.duration)).foregroundStyle(WPalette.sourdine)
                }
                .font(.system(size: 11, design: .monospaced)).padding(.top, 5)
                HStack {
                    TransportTrio(isPlaying: entry.isPlaying, circle: 34, iconSize: 17, spacing: 16)
                    Spacer()
                    Image(systemName: entry.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 17)).foregroundStyle(WPalette.cuivre)
                }
                .padding(.top, 9)
            }
        }
    }
}

// MARK: - Format grand

private struct LargeView: View {
    let entry: NowPlayingEntry
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Lecture en cours", systemImage: "opticaldisc")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(WPalette.cuivre)
                Spacer()
                Text("Sillon").font(.system(size: 11, design: .serif)).foregroundStyle(WPalette.sourdine)
            }
            HStack(spacing: 14) {
                CoverSpectrum(size: 96)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title).font(.system(size: 17, design: .serif)).foregroundStyle(WPalette.texte).lineLimit(2)
                    Text(entry.artist).font(.system(size: 13, weight: .medium)).foregroundStyle(WPalette.sourdine).lineLimit(1)
                    Text(entry.album).font(.system(size: 12)).foregroundStyle(WPalette.sourdine).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            ProgressLine(fraction: entry.fraction).padding(.top, 14)
            HStack {
                Text(mmss(entry.elapsed)); Spacer(); Text(mmss(entry.duration))
            }
            .font(.system(size: 11, design: .monospaced)).foregroundStyle(WPalette.sourdine).padding(.top, 5)
            Text(entry.quality).font(.system(size: 11, design: .monospaced)).foregroundStyle(WPalette.teal).padding(.top, 3)
            Spacer(minLength: 0)
            HStack {
                Image(systemName: entry.isFavorite ? "heart.fill" : "heart").foregroundStyle(WPalette.cuivre)
                Spacer()
                TransportTrio(isPlaying: entry.isPlaying, circle: 46, iconSize: 19, spacing: 22)
                Spacer()
                Image(systemName: "list.bullet").foregroundStyle(WPalette.sourdine)
            }
            .font(.system(size: 19)).padding(.top, 8)
        }
    }
}

// MARK: - Widget

struct SillonWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: NowPlayingEntry

    var body: some View {
        Group {
            switch family {
            case .systemLarge: LargeView(entry: entry)
            default: MediumView(entry: entry)
            }
        }
        .containerBackground(WPalette.fond, for: .widget)
    }
}

struct SillonWidget: Widget {
    let kind = "SillonWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            SillonWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Lecture en cours")
        .description("La lecture en cours dans Sillon, avec les commandes.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

#Preview("Medium", as: .systemMedium) {
    SillonWidget()
} timeline: {
    NowPlayingEntry.sample
}

#Preview("Grand", as: .systemLarge) {
    SillonWidget()
} timeline: {
    NowPlayingEntry.sample
}
