import SwiftUI

/// Récupère les paroles d'un morceau À LA DEMANDE, à partir de son `remoteID` et de son serveur.
/// Calqué sur `ArtworkLoader` : providers authentifiés mis en cache par serveur, résultats mis en
/// cache par identifiant de morceau (`track.id`) pour éviter de re-requêter à chaque réouverture.
/// LECTURE SEULE serveur : aucune écriture, aucune persistance SwiftData.
@MainActor
@Observable
final class LyricsLoader {
    @ObservationIgnored private var providers: [UUID: any ServerProvider] = [:]
    /// Cache positif ET négatif : une valeur `nil` mémorise « pas de paroles » pour ne pas re-tenter.
    @ObservationIgnored private var cache: [String: TrackLyrics?] = [:]

    nonisolated init() {}

    /// Renvoie les paroles du morceau, ou `nil` si indisponible (aucune parole, serveur muet,
    /// erreur réseau → l'UI affiche un état « Pas de paroles »).
    func lyrics(for track: Track) async -> TrackLyrics? {
        guard let server = track.server else { return nil }
        if let cached = cache[track.id] { return cached }   // hit positif ou négatif
        do {
            let provider = try provider(for: server)
            let result = try await provider.lyrics(forTrackID: track.remoteID)
            cache[track.id] = result
            return result
        } catch {
            // On NE met PAS en cache un échec réseau (pour retenter plus tard), contrairement au
            // « pas de paroles » légitime (déjà mis en cache ci-dessus).
            return nil
        }
    }

    private func provider(for server: ServerAccount) throws -> any ServerProvider {
        if let existing = providers[server.id] { return existing }
        let created = try ServerProviderFactory.makeProvider(for: server)
        providers[server.id] = created
        return created
    }
}

extension EnvironmentValues {
    @Entry var lyricsLoader = LyricsLoader()
}
