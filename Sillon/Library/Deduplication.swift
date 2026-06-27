import Foundation
import SwiftData

/// Retrouve les copies d'un même album/titre/artiste réparties sur plusieurs serveurs (mêmes clés de
/// dédup que l'affichage). Sert à garder cohérents les états par-copie : favori (propagé à toutes les
/// copies) et lecture hors-ligne (utiliser le fichier téléchargé d'une copie quelconque du groupe).
@MainActor
enum DuplicateResolver {
    /// `caseInsensitive` : élargit le pré-filtre de titre/nom (`localizedStandardContains`) pour
    /// rattraper une copie dont la casse ou les diacritiques divergent entre serveurs (ex. « HEY JUDE »
    /// vs « Hey Jude »). Réservé à la propagation de favori (action ponctuelle) ; le chemin de lecture
    /// hors-ligne garde l'égalité exacte indexée (`== title`) pour rester rapide à chaque morceau.
    static func albumCopies(of album: Album, in context: ModelContext, caseInsensitive: Bool = false) -> [Album] {
        // La propagation d'état (favori, lecture locale) ne doit JAMAIS fusionner des éléments dont
        // l'identité n'est pas établie. Si l'identité n'est pas discriminante (ni artiste ni année :
        // la clé s'effondrerait en « titre|| »), on ne considère que l'album lui-même comme copie.
        let artist = DedupKey.normalize(album.artistNameSnapshot ?? album.artist?.name)
        guard !artist.isEmpty || album.year != nil else { return [album] }
        let title = album.title
        let key = DedupKey.album(album)
        // Pré-filtre par titre (exact et indexé par défaut, élargi à la casse/diacritiques si demandé) ;
        // le filtre `DedupKey` ci-dessous re-resserre sur l'identité réelle.
        let predicate: Predicate<Album> = caseInsensitive
            ? #Predicate { $0.title.localizedStandardContains(title) }
            : #Predicate { $0.title == title }
        let candidates = (try? context.fetch(FetchDescriptor<Album>(predicate: predicate))) ?? []
        return candidates.filter { DedupKey.album($0) == key }
    }

    static func trackCopies(of track: Track, in context: ModelContext, caseInsensitive: Bool = false) -> [Track] {
        // Identité non fiable sans artiste (homonymes de durée proche) → on ne propage qu'au titre lui-même.
        guard !DedupKey.normalize(track.artistNameSnapshot ?? track.album?.artist?.name).isEmpty else { return [track] }
        let title = track.title
        let base = DedupKey.trackBase(track)
        let secs = DedupKey.seconds(track)
        let predicate: Predicate<Track> = caseInsensitive
            ? #Predicate { $0.title.localizedStandardContains(title) }
            : #Predicate { $0.title == title }
        let candidates = (try? context.fetch(FetchDescriptor<Track>(predicate: predicate))) ?? []
        return candidates.filter { DedupKey.trackBase($0) == base && abs(DedupKey.seconds($0) - secs) <= 2 }
    }

    static func artistCopies(of artist: Artist, in context: ModelContext, caseInsensitive: Bool = false) -> [Artist] {
        guard !DedupKey.normalize(artist.name).isEmpty else { return [artist] }
        let name = artist.name
        let key = DedupKey.artist(artist)
        let predicate: Predicate<Artist> = caseInsensitive
            ? #Predicate { $0.name.localizedStandardContains(name) }
            : #Predicate { $0.name == name }
        let candidates = (try? context.fetch(FetchDescriptor<Artist>(predicate: predicate))) ?? []
        return candidates.filter { DedupKey.artist($0) == key }
    }
}

/// Déduplication d'AFFICHAGE entre serveurs (aucune écriture en base, zéro migration) : quand le
/// même album/titre est présent sur plusieurs serveurs, on n'affiche qu'un représentant — la copie
/// du serveur le plus prioritaire (`ServerAccount.sortOrder`, puis type, puis ancienneté).
enum DedupKey {
    /// Clé normalisée : minuscule, sans accents ni ponctuation, espaces compactés.
    static func normalize(_ s: String?) -> String {
        guard let s else { return "" }
        return s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Identité d'un album entre serveurs : titre + artiste + année (les bibliothèques miroir
    /// partagent ces métadonnées). L'année évite de fusionner une réédition d'année différente.
    static func album(_ a: Album) -> String {
        let artist = a.artistNameSnapshot ?? a.artist?.name
        return "\(normalize(a.title))|\(normalize(artist))|\(a.year ?? 0)"
    }

    /// Base d'identité d'un titre : titre + artiste. On évite délibérément les métadonnées d'album et
    /// les n° de piste/disque : elles divergent souvent entre serveurs (ex. « [Unknown Album] » côté
    /// Navidrome, n° de disque absent…). La durée discrimine les enregistrements distincts de même
    /// titre, mais elle est comparée AVEC TOLÉRANCE dans `dedupedTracks` (±2 s) car un même fichier
    /// peut être rapporté à 1 s près d'un serveur à l'autre.
    static func trackBase(_ t: Track) -> String {
        let artist = t.artistNameSnapshot ?? t.album?.artist?.name
        return "\(normalize(t.title))|\(normalize(artist))"
    }

    static func seconds(_ t: Track) -> Int {
        t.durationSeconds.isFinite ? Int(t.durationSeconds.rounded()) : 0
    }

    /// Identité d'un artiste entre serveurs : son nom normalisé.
    static func artist(_ a: Artist) -> String { normalize(a.name) }

    /// Rang de priorité d'un serveur (plus petit = préféré) : ordre utilisateur, puis type
    /// (local > Jellyfin > Subsonic), puis ancienneté. Sert à choisir la copie gagnante.
    static func rank(_ s: ServerAccount?) -> (Int, Int, Double) {
        (s?.sortOrder ?? 0,
         s?.type.dedupRank ?? 9,
         s?.createdAt.timeIntervalSince1970 ?? .greatestFiniteMagnitude)
    }
}

extension Array where Element == Album {
    /// Regroupe les albums identiques entre serveurs et renvoie un représentant (copie gagnante)
    /// par groupe, avec le nombre de sources. Préserve l'ordre d'apparition (donc le tri du `@Query`).
    func dedupedAlbums(merge: Bool) -> [(album: Album, sourceCount: Int)] {
        guard merge else { return map { ($0, 1) } }
        var groups: [String: [Album]] = [:]
        var order: [String] = []
        for a in self {
            let k = DedupKey.album(a)
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(a)
        }
        return order.map { k in
            let copies = groups[k]!
            let rep = copies.min { DedupKey.rank($0.server) < DedupKey.rank($1.server) }!
            return (rep, copies.count)
        }
    }
}

extension Array where Element == Artist {
    /// Déduplique les artistes de même nom entre serveurs en gardant la copie du serveur prioritaire.
    /// (Bibliothèques miroir : ses albums viennent alors du serveur représentant.)
    func dedupedArtists(merge: Bool) -> [Artist] {
        guard merge else { return self }
        var groups: [String: [Artist]] = [:]
        var order: [String] = []
        for a in self {
            let k = DedupKey.artist(a)
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(a)
        }
        return order.map { k in
            // Représentant : la copie qui a le plus d'albums LIÉS (certains serveurs, ex. Jellyfin,
            // ne peuplent pas la relation artiste→album), puis le serveur prioritaire en cas d'égalité.
            // On évite ainsi un artiste représentant vide alors qu'une autre source a sa discographie.
            groups[k]!.min { a, b in
                if a.albums.count != b.albums.count { return a.albums.count > b.albums.count }
                return DedupKey.rank(a.server) < DedupKey.rank(b.server)
            }!
        }
    }
}

extension Array where Element == Track {
    /// Déduplique les titres identiques entre serveurs en gardant la copie du serveur prioritaire.
    /// Regroupe par (titre, artiste) puis fusionne les durées proches (±2 s) — tolérance nécessaire
    /// car un même fichier peut être rapporté à ±1 s d'un serveur à l'autre. Préserve l'ordre
    /// d'apparition (donc le tri du `@Query`).
    func dedupedTracks(merge: Bool) -> [Track] {
        guard merge else { return self }
        var result: [Track] = []
        // Par clé (titre|artiste) : durées déjà retenues + index du représentant dans `result`.
        var buckets: [String: [(seconds: Int, repIndex: Int)]] = [:]
        for t in self {
            let key = DedupKey.trackBase(t)
            let secs = DedupKey.seconds(t)
            if let match = buckets[key]?.first(where: { abs($0.seconds - secs) <= 2 }) {
                // Doublon : on conserve la copie du serveur le plus prioritaire (position inchangée).
                if DedupKey.rank(t.server) < DedupKey.rank(result[match.repIndex].server) {
                    result[match.repIndex] = t
                }
            } else {
                buckets[key, default: []].append((secs, result.count))
                result.append(t)
            }
        }
        return result
    }
}
