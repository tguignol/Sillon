import Foundation

/// Sortie audio courante : transport (Bluetooth / AirPlay / filaire / haut-parleur), appareil et
/// fréquence de sortie.
///
/// IMPORTANT — codec Bluetooth : le codec de transmission A2DP (SBC / AAC / aptX / LDAC) **n'est pas
/// exposé par les API publiques iOS/macOS**. Le champ `codec` est donc `nil` sur ces plateformes ;
/// il sera renseigné par la future version Android (via `BluetoothCodecConfig`). En attendant, on
/// affiche le transport, qui est l'information la plus précise disponible côté Apple.
struct AudioOutput: Equatable {
    enum Transport: String, Equatable {
        case bluetooth, airPlay, wired, speaker, builtIn, other

        var label: String {
            switch self {
            case .bluetooth: "Bluetooth"
            case .airPlay: "AirPlay"
            case .wired: "Filaire"
            case .speaker: "Haut-parleur"
            case .builtIn: "Écouteur"
            case .other: "Sortie"
            }
        }

        var systemImage: String {
            switch self {
            case .bluetooth: "wave.3.right"
            case .airPlay: "airplayaudio"
            case .wired: "headphones"
            case .speaker: "speaker.wave.2.fill"
            case .builtIn: "iphone"
            case .other: "hifispeaker.fill"
            }
        }
    }

    var transport: Transport
    var deviceName: String?
    var sampleRate: Double?
    /// Codec de transmission Bluetooth — renseigné uniquement sur Android (nil sur iOS/macOS).
    var codec: String?

    /// Libellé compact : « AirPods Pro · Bluetooth · 48 kHz » (le codec remplace le transport s'il est
    /// connu, ex. « AirPods Pro · AAC · 48 kHz » sur Android).
    var summary: String {
        var parts: [String] = []
        // Le nom d'appareil n'est informatif que pour une sortie externe (« AirPods Pro »…) ; pour le
        // HP/écouteur interne il vaut « Speaker »/« Receiver » et ferait doublon avec le transport.
        let showsDevice = transport == .bluetooth || transport == .airPlay || transport == .wired
        if showsDevice, let deviceName, !deviceName.isEmpty { parts.append(deviceName) }
        parts.append(codec ?? transport.label)
        if let sampleRate, sampleRate > 0 {
            parts.append(String(format: "%.3g kHz", sampleRate / 1000))
        }
        return parts.joined(separator: " · ")
    }
}
