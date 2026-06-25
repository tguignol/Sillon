#if DEBUG
import Foundation
import SwiftData

/// Amorçage de test, **compilé uniquement en DEBUG**. Si l'app est lancée avec les variables
/// d'environnement `SILLON_DEMO_*`, crée le serveur correspondant (secret écrit en Keychain) et
/// lance une vraie synchronisation. En l'absence de ces variables, ne fait **rien** — donc
/// totalement inoffensif en usage normal.
///
/// But : permettre une validation de bout en bout sur le simulateur (vraie synchro contre un vrai
/// serveur) sans saisie manuelle ni contrôle d'écran, par exemple :
///
/// ```
/// SIMCTL_CHILD_SILLON_DEMO_TYPE=jellyfin \
/// SIMCTL_CHILD_SILLON_DEMO_URL=http://exemple:8096 \
/// SIMCTL_CHILD_SILLON_DEMO_USER=thomas \
/// SIMCTL_CHILD_SILLON_DEMO_PW=… \
/// xcrun simctl launch booted kohlnet.Sillon
/// ```
///
/// Aucune donnée d'identification n'est codée en dur ici : tout vient de l'environnement de lancement.
enum DebugBootstrap {
    @MainActor
    static func runIfRequested(context: ModelContext) async {
        let env = ProcessInfo.processInfo.environment
        guard let typeRaw = env["SILLON_DEMO_TYPE"], let type = ServerType(rawValue: typeRaw),
              let urlString = env["SILLON_DEMO_URL"],
              let user = env["SILLON_DEMO_USER"],
              let password = env["SILLON_DEMO_PW"], !password.isEmpty
        else { return }

        let existing = (try? context.fetch(FetchDescriptor<ServerAccount>())) ?? []
        let server: ServerAccount
        if let found = existing.first(where: { $0.baseURLString == urlString && $0.username == user && $0.type == type }) {
            server = found
        } else {
            server = ServerAccount(name: env["SILLON_DEMO_NAME"] ?? type.displayName,
                                   type: type, baseURLString: urlString, username: user)
            try? KeychainStore.save(password, for: server.id, field: .password)
            context.insert(server)
        }

        do {
            try await LibrarySyncService.synchronize(server, context: context)
            let artists = (try? context.fetch(FetchDescriptor<Artist>()))?.count ?? -1
            let albums = (try? context.fetch(FetchDescriptor<Album>()))?.count ?? -1
            let tracks = (try? context.fetch(FetchDescriptor<Track>()))?.count ?? -1
            // NSLog (et non print) pour apparaître dans le journal unifié (`log show`).
            NSLog("SILLON_DEMO sync OK \(type.rawValue): \(artists) artistes, \(albums) albums, \(tracks) titres")
        } catch {
            NSLog("SILLON_DEMO sync ECHEC \(type.rawValue): \(error)")
        }
    }
}
#endif
