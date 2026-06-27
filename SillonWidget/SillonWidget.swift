//
//  SillonWidget.swift
//  SillonWidget
//
//  Widget « Lecture en cours » de Sillon — formats medium (pleine largeur, demi-hauteur) et grand.
//  Phase 2 : VRAIES données lues dans le conteneur partagé (App Group `group.kohlnet.Sillon`),
//  alimenté par l'app (`NowPlayingWidgetBridge`). Progression vivante via `timerInterval` pendant la
//  lecture. Les boutons interactifs (AudioPlaybackIntent) arrivent à l'étape suivante.
//

import WidgetKit
import SwiftUI
import UIKit

// MARK: - Palette locale (mêmes teintes que l'app)

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

// MARK: - Lecture du conteneur partagé (App Group)

private enum Shared {
    static let appGroup = "group.kohlnet.Sillon"

    static func cover() -> UIImage? {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("np-cover.dat"),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Donnée affichée

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let isEmpty: Bool
    let title: String
    let artist: String
    let album: String
    let elapsed: Double
    let duration: Double
    let anchor: Date          // instant où `elapsed` a été échantillonné par l'app
    let quality: String
    let isPlaying: Bool
    let isFavorite: Bool
    let cover: UIImage?

    var fraction: Double { duration > 0 ? min(1, elapsed / duration) : 0 }
    /// Bornes virtuelles pour une progression vivante (le morceau a « commencé » à `anchor - elapsed`).
    var virtualStart: Date { anchor.addingTimeInterval(-elapsed) }
    var virtualEnd: Date { virtualStart.addingTimeInterval(max(1, duration)) }
    /// Vrai si on peut animer la progression côté widget sans rechargement (lecture en cours).
    var liveProgress: Bool { isPlaying && duration > 1 }

    static let sample = NowPlayingEntry(
        date: .now, isEmpty: false, title: "Come Back and Stay", artist: "Paul Young",
        album: "From Time to Time", elapsed: 21, duration: 264, anchor: .now,
        quality: "FLAC · 44,1 kHz", isPlaying: true, isFavorite: true, cover: nil)

    static let empty = NowPlayingEntry(
        date: .now, isEmpty: true, title: "", artist: "", album: "", elapsed: 0, duration: 0,
        anchor: .now, quality: "", isPlaying: false, isFavorite: false, cover: nil)
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(context.isPreview ? .sample : read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        // Une entrée : l'app recharge le widget (`WidgetCenter`) à chaque changement d'état.
        completion(Timeline(entries: [read()], policy: .never))
    }

    private func read() -> NowPlayingEntry {
        guard let d = UserDefaults(suiteName: Shared.appGroup), d.bool(forKey: "np.has") else { return .empty }
        return NowPlayingEntry(
            date: .now, isEmpty: false,
            title: d.string(forKey: "np.title") ?? "",
            artist: d.string(forKey: "np.artist") ?? "",
            album: d.string(forKey: "np.album") ?? "",
            elapsed: d.double(forKey: "np.elapsed"),
            duration: d.double(forKey: "np.duration"),
            anchor: Date(timeIntervalSince1970: d.double(forKey: "np.anchor")),
            quality: d.string(forKey: "np.quality") ?? "",
            isPlaying: d.bool(forKey: "np.playing"),
            isFavorite: d.bool(forKey: "np.favorite"),
            cover: Shared.cover())
    }
}

// MARK: - Sous-vues

/// Pochette (réelle si partagée, sinon « vinyle » placeholder) entourée du spectre statique.
private struct CoverSpectrum: View {
    var size: CGFloat
    var cover: UIImage?
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
            Group {
                if let cover {
                    Image(uiImage: cover).resizable().scaledToFill()
                } else {
                    Circle().fill(WPalette.pochette)
                        .overlay(Circle().fill(WPalette.pochette.opacity(0.55)).frame(width: size * 0.14, height: size * 0.14))
                        .overlay(Circle().fill(WPalette.fond).frame(width: size * 0.03, height: size * 0.03))
                }
            }
            .frame(width: size * 0.7, height: size * 0.7)
            .clipShape(Circle())
        }
        .frame(width: size, height: size)
    }
}

/// Barre de progression : vivante (timerInterval) en lecture, statique sinon.
private struct PlaybackProgress: View {
    let entry: NowPlayingEntry
    var body: some View {
        Group {
            if entry.liveProgress {
                ProgressView(timerInterval: entry.virtualStart...entry.virtualEnd, countsDown: false) {
                    EmptyView()
                } currentValueLabel: { EmptyView() }
            } else {
                ProgressView(value: entry.fraction)
            }
        }
        .progressViewStyle(.linear)
        .tint(WPalette.cuivre)
    }
}

/// Temps écoulé : compte en direct pendant la lecture.
private struct ElapsedLabel: View {
    let entry: NowPlayingEntry
    var body: some View {
        if entry.liveProgress {
            Text(timerInterval: entry.virtualStart...entry.virtualEnd, countsDown: false)
                .monospacedDigit()
        } else {
            Text(mmss(entry.elapsed))
        }
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

// MARK: - États vides

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "opticaldisc").font(.system(size: 26)).foregroundStyle(WPalette.cuivre)
            Text("Rien en lecture").font(.system(size: 14, weight: .medium)).foregroundStyle(WPalette.texte)
            Text("Sillon").font(.system(size: 12, design: .serif)).foregroundStyle(WPalette.sourdine)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Format medium

private struct MediumView: View {
    let entry: NowPlayingEntry
    var body: some View {
        HStack(spacing: 14) {
            CoverSpectrum(size: 104, cover: entry.cover)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.title).font(.system(size: 16, design: .serif)).foregroundStyle(WPalette.texte).lineLimit(1)
                Text(entry.artist).font(.system(size: 12, weight: .medium)).foregroundStyle(WPalette.sourdine).lineLimit(1)
                PlaybackProgress(entry: entry).padding(.top, 10)
                HStack {
                    ElapsedLabel(entry: entry).foregroundStyle(WPalette.sourdine)
                    Spacer()
                    Text(entry.quality).foregroundStyle(WPalette.teal).lineLimit(1)
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
                CoverSpectrum(size: 96, cover: entry.cover)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title).font(.system(size: 17, design: .serif)).foregroundStyle(WPalette.texte).lineLimit(2)
                    Text(entry.artist).font(.system(size: 13, weight: .medium)).foregroundStyle(WPalette.sourdine).lineLimit(1)
                    Text(entry.album).font(.system(size: 12)).foregroundStyle(WPalette.sourdine).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            PlaybackProgress(entry: entry).padding(.top, 14)
            HStack {
                ElapsedLabel(entry: entry); Spacer(); Text(mmss(entry.duration))
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
            if entry.isEmpty {
                EmptyStateView()
            } else if family == .systemLarge {
                LargeView(entry: entry)
            } else {
                MediumView(entry: entry)
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
