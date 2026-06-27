import Foundation
import AVFoundation
import Accelerate

/// Analyseur de spectre audio temps réel : pose un *tap* sur un nœud du moteur, calcule une FFT
/// (Accelerate / vDSP) sur chaque tampon et publie des magnitudes normalisées (0…1) regroupées en
/// bandes réparties logarithmiquement.
///
/// Le tap s'exécute sur un thread audio temps réel : le calcul y est fait (rapide pour 1024
/// échantillons) puis le résultat est transmis via `onUpdate` (l'appelant rebascule sur le MainActor).
final class AudioSpectrumAnalyzer {
    let bandCount: Int
    let waveformCount: Int

    private let fftSize: Int
    private let halfSize: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private var window: [Float]

    /// Appelé sur le thread audio avec (magnitudes FFT 0…1, forme d'onde temporelle -1…1).
    /// L'appelant doit reposter sur le MainActor.
    private var onUpdate: (([Float], [Float]) -> Void)?
    private weak var tappedNode: AVAudioNode?

    /// Synchronise l'usage de `fftSetup` / `onUpdate` (thread audio temps réel) avec le démontage
    /// (MainActor / `deinit`) : sans ça, un callback de tap en vol pourrait lire un `onUpdate` muté
    /// ou utiliser `fftSetup` APRÈS sa destruction (use-after-free). Verrou non contendu hors démontage
    /// — acceptable pour ce tap de visualisation (≠ chemin de lecture audio).
    private let lock = NSLock()
    private var alive = true

    init(bandCount: Int = 48, fftSize: Int = 1024, waveformCount: Int = 128) {
        self.bandCount = bandCount
        self.waveformCount = waveformCount
        self.fftSize = fftSize
        self.halfSize = fftSize / 2
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        self.window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        removeTap()                       // plus AUCUN nouveau callback de tap après ça
        lock.lock()
        alive = false                     // un callback résiduel verra ceci et n'utilisera pas fftSetup
        vDSP_destroy_fftsetup(fftSetup)   // détruit SOUS le verrou : aucun process() ne peut l'utiliser en même temps
        lock.unlock()
    }

    func installTap(on node: AVAudioNode, onUpdate: @escaping ([Float], [Float]) -> Void) {
        removeTap()
        lock.lock(); self.onUpdate = onUpdate; lock.unlock()
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        tappedNode = node
    }

    func removeTap() {
        tappedNode?.removeTap(onBus: 0)
        tappedNode = nil
        lock.lock(); onUpdate = nil; lock.unlock()
    }

    // MARK: - Traitement (thread audio)

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData, Int(buffer.frameLength) >= fftSize else { return }
        // Tout l'usage de fftSetup + onUpdate sous verrou : empêche un démontage concurrent (destruction
        // de fftSetup / mise à nil d'onUpdate) pendant le calcul. `alive` == false ⇒ on ne touche pas fftSetup.
        lock.lock()
        defer { lock.unlock() }
        guard alive, let onUpdate else { return }
        let samples = channelData[0]

        // Forme d'onde temporelle (oscilloscope) : sous-échantillonnage des échantillons bruts.
        var waveform = [Float](repeating: 0, count: waveformCount)
        let stride = max(1, fftSize / waveformCount)
        for i in 0..<waveformCount {
            waveform[i] = samples[i * stride]
        }

        // Fenêtre de Hann sur le 1er canal pour la FFT.
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        var real = [Float](repeating: 0, count: halfSize)
        var imag = [Float](repeating: 0, count: halfSize)
        var magnitudes = [Float](repeating: 0, count: halfSize)

        real.withUnsafeMutableBufferPointer { realP in
            imag.withUnsafeMutableBufferPointer { imagP in
                var split = DSPSplitComplex(realp: realP.baseAddress!, imagp: imagP.baseAddress!)
                windowed.withUnsafeBufferPointer { samples in
                    samples.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(halfSize))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }

        // Puissance -> amplitude.
        var amplitudes = [Float](repeating: 0, count: halfSize)
        var elements = Int32(halfSize)
        vvsqrtf(&amplitudes, magnitudes, &elements)

        onUpdate(groupIntoBands(amplitudes), waveform)
    }

    /// Regroupe les magnitudes en `bandCount` bandes log, normalisées en 0…1 (échelle dB perceptuelle).
    private func groupIntoBands(_ amplitudes: [Float]) -> [Float] {
        let n = amplitudes.count
        guard n > 1 else { return [Float](repeating: 0, count: bandCount) }
        var bands = [Float](repeating: 0, count: bandCount)
        let minBin = 1.0
        let maxBin = Double(n)

        for b in 0..<bandCount {
            let lo = Int(minBin * pow(maxBin / minBin, Double(b) / Double(bandCount)))
            var hi = Int(minBin * pow(maxBin / minBin, Double(b + 1) / Double(bandCount)))
            hi = min(max(hi, lo + 1), n)
            let lower = min(lo, n - 1)

            var sum: Float = 0
            for i in lower..<hi { sum += amplitudes[i] }
            let avg = hi > lower ? sum / Float(hi - lower) : 0

            // Les magnitudes FFT (vDSP, non normalisées) sont grandes → sans recalage la fenêtre dB
            // saturait (tout collé à 1 = anneau plein figé). On recale sur une plage plus haute pour
            // retrouver une vraie dynamique 0…1 : les bandes varient et « bougent » au lieu de saturer.
            let db = 20 * log10(avg + 1e-7)
            bands[b] = max(0, min(1, (db + 20) / 50))   // ~ -20 dB … +30 dB -> 0 … 1
        }
        return bands
    }
}
