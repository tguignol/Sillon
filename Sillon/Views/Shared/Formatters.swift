import Foundation

extension Double {
    /// Durée d'un morceau au format `m:ss` (ou `h:mm:ss` au-delà d'une heure).
    var asTrackDuration: String {
        guard isFinite, self >= 0 else { return "—:—" }
        let total = Int(rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

extension Track {
    /// Badge technique compact (codec + bitrate), ex: "FLAC · 1024 kbps". Vide si inconnu.
    var technicalBadge: String {
        var parts: [String] = []
        if let format, !format.isEmpty { parts.append(format.uppercased()) }
        if let bitrate, bitrate > 0 { parts.append("\(bitrate) kbps") }
        return parts.joined(separator: " · ")
    }
}
