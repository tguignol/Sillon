# Sillon — Phase 1 complète

Lecteur musical SwiftUI multiplateforme (iOS 26 / macOS Tahoe), target unique, connecté à des
serveurs personnels : **Jellyfin**, **Navidrome / Subsonic**, et **fichiers locaux**.

La Phase 1 (cœur de l'app) est terminée — voir `Sillon/Docs/ROADMAP.md`. Tout a été **validé sur le
simulateur iOS 26.5 contre de vrais serveurs** (synchro de ~16 k titres, téléchargements, lecture
offline avec égaliseur, favoris, playlists).

## Fonctionnalités (commits 1 → 7)

- **Serveurs** : ajout Jellyfin / Navidrome-Subsonic / dossier local, test de connexion, secrets en
  Keychain (jamais en base ni sur GitHub).
- **Synchronisation** : moteur full/delta, upsert SwiftData, horodatage + curseur, pagination
  (grosses bibliothèques), progression.
- **Bibliothèque & Accueil** : Artistes / Albums / Titres / Playlists, écran d'accueil « disquaire »
  (sections horizontales), pochettes réelles avec repli placeholder.
- **Téléchargements** : `DownloadManager` (URLSession de fond), arborescence serveur
  `<Serveur>/<Artiste>/<Album>/<NN - Titre>.<ext>`, file visible, lecture offline-first.
- **Lecteur + Égaliseur** : `AVAudioEngine` (player → `AVAudioUnitEQ` → mixer), écran lecteur avec
  *groove ring* signature, barre -10s/+10s, cœur favori, sélecteur AirPlay, mini-lecteur ancré,
  égaliseur 6-12 bandes (sauvegarde du dernier état).
- **Favoris & Playlists** : toggle cœur partout, onglet Favoris + « Mixer les favoris », CRUD
  playlists locales + réordonnancement glisser-déposer.

> **Lecture seule côté serveur** : l'app ne modifie ni n'efface jamais de données sur les serveurs.
> Favoris et playlists sont **locaux à l'app**.

## Architecture (dossiers sous `Sillon/`)

```
App/            SillonApp, RootTabView, SillonAppDelegate (iOS), DebugBootstrap (DEBUG)
Models/         ServerAccount, Artist, Album, Track, Playlist(+Item), DownloadTask, EQSettings
Networking/     ServerProvider (protocole acteur) + Jellyfin / Subsonic / Local + factory
Persistence/    ModelContainerFactory (schéma SwiftData)
Security/       KeychainStore
Sync/           LibrarySyncService
Downloads/      DownloadManager, DownloadSessionDelegate, DownloadFileLayout
Player/         PlayerController, EQBands, EQSettingsStore
Favorites/      Favoritable
Playlists/      PlaylistActions
DesignSystem/   Theme (palette / typo / espacement)
Views/          App / Servers / Settings / Library / Home / Favorites / Playlists / Player / Downloads / Shared
Docs/           ROADMAP, DECISIONS (#1-31), DESIGN_SYSTEM
```

## Compilation & tests

Vérifié sur Xcode 26 (SDK iOS 26.5 / macOS 26.5) :

```
xcodebuild build -scheme Sillon -destination 'platform=macOS'
xcodebuild build -scheme Sillon -destination 'generic/platform=iOS Simulator'
xcodebuild test  -scheme Sillon -destination 'platform=macOS' -only-testing:SillonTests
```

Le `.xcodeproj` utilise des **groupes synchronisés au système de fichiers** : les nouveaux fichiers
Swift déposés dans les dossiers sont repris automatiquement. Après un `git pull`, ouvrez le projet et
**Cmd + R**.

Tests unitaires (`SillonTests`) : moteur de sync, arborescence de téléchargement, bandes EQ, actions
de playlist. Tests d'intégration réseau (`ServerIntegrationTests`) **désactivés par défaut** (lus
depuis l'environnement, aucun secret committé).

### À vérifier côté projet Xcode

- macOS : App Sandbox ▸ Network ▸ Outgoing Connections (Client) (déjà dans les entitlements).
- ATS : `NSAllowsArbitraryLoads` est activé (serveurs `http://` / cert auto-signé).
- iOS : `UIBackgroundModes: audio` (lecture en arrière-plan).
- Bundle Identifier aligné avec `service` dans `Security/KeychainStore.swift`.

## Et après ?

Phase 1 terminée → **pause pour validation**. La Phase 2 (proposée, non développée) ne sera lancée
qu'après accord explicite.
