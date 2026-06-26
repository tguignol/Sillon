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

extension String {
    /// Libellé d'affichage propre d'un codec audio brut (style ffmpeg / suffixe de fichier) :
    /// "flac" → "FLAC", "alac" → "ALAC", "pcm_s24le" → "PCM 24 bit", "aac"/"m4a" → "AAC".
    /// Repli : version en capitales.
    var audioCodecLabel: String {
        let raw = trimmingCharacters(in: .whitespaces).lowercased()
        switch raw {
        case "flac": return "FLAC"
        case "alac": return "ALAC"
        case "aac", "m4a", "mp4", "mp4a": return "AAC"
        case "mp3", "mpeg", "mp2": return "MP3"
        case "opus": return "Opus"
        case "vorbis", "ogg": return "OGG"
        case "wav", "wave": return "WAV"
        case "aiff", "aif": return "AIFF"
        case "ac3": return "AC-3"
        case "eac3": return "E-AC-3"
        case "dts": return "DTS"
        case "wma": return "WMA"
        default:
            // PCM (ex. ffmpeg : pcm_s16le, pcm_s24le, pcm_f32le) → « PCM N bit ».
            if raw.hasPrefix("pcm") {
                if let depth = ["8", "16", "24", "32"].first(where: { raw.contains("s\($0)") || raw.contains("u\($0)") || raw.contains("f\($0)") }) {
                    return "PCM \(depth) bit"
                }
                return "PCM"
            }
            return uppercased()
        }
    }
}

extension Track {
    /// Badge technique compact (codec + bitrate), ex: "FLAC · 1024 kbps". Vide si inconnu.
    var technicalBadge: String {
        var parts: [String] = []
        if let format, !format.isEmpty { parts.append(format.audioCodecLabel) }
        if let bitrate, bitrate > 0 { parts.append("\(bitrate) kbps") }
        return parts.joined(separator: " · ")
    }
}
