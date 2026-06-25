# Sillon — Commit 3/7 de la Phase 1

App de lecture musicale connectée à des serveurs personnels (Jellyfin, Navidrome/Subsonic,
fichiers locaux), SwiftUI multiplateforme (iOS 26 / macOS Tahoe), target unique.

Ce commit ajoute le **moteur de synchronisation** et la **bibliothèque réelle** (écrans Accueil +
Bibliothèque) par-dessus les fondations des commits 1 et 2 (toujours présentes).
Voir `Sillon/Docs/ROADMAP.md` pour la suite.

## Contenu ajouté par ce commit

```
DesignSystem/
  Theme.swift                     → palette / typo / espacement (concrétise Docs/DESIGN_SYSTEM.md)
Sync/
  LibrarySyncService.swift        → moteur full/delta : upsert SwiftData, horodatage + curseur, progression
Views/Home/
  HomeView.swift                  → accueil "disquaire" : sections horizontales à tailles inégales
Views/Library/
  LibraryRootView.swift           → sélecteur Artistes / Albums / Titres / Playlists
  ArtistsListView.swift           → liste artistes + détail (albums en grille)
  AlbumsGridView.swift            → grille albums + détail (liste des morceaux)
  TracksListView.swift            → liste à plat de tous les titres
  PlaylistsListView.swift         → playlists locales (création au commit 6)
Views/Shared/
  CoverArtView.swift              → pochette : artwork réel + fallback placeholder cuivré
  ArtworkLoader.swift             → résolution/cache des URLs de pochette (providers authentifiés)
  AlbumCard.swift, TrackRowView.swift, Formatters.swift, PreviewData.swift
```

Modifiés : `ViewModels/ServerListViewModel.swift` (pilote le moteur de sync), `Views/Servers/
ServerRowView.swift` (barre de progression réelle), `App/RootTabView.swift` (Accueil + Bibliothèque
câblés), `App/SillonApp.swift` (injection de l'`ArtworkLoader`).

**Désormais, "Synchroniser" persiste réellement la bibliothèque** : artistes, albums et morceaux
apparaissent dans les onglets Accueil et Bibliothèque après une synchro réussie (cf. `Docs/DECISIONS.md`
#14 à #19 pour les choix de ce commit). Les *favoris* sont affichés en lecture seule ; leur toggle
et l'écran Favoris dédié arrivent au commit 6.

## Compilation vérifiée

Ce commit a été compilé avec succès sur les deux plateformes (Xcode 26 / SDK iOS 26.5 et macOS 26.5) :

```
xcodebuild build -scheme Sillon -destination 'platform=macOS'
xcodebuild build -scheme Sillon -destination 'generic/platform=iOS Simulator'
```

Note : un `AppIcon.appiconset` vide (placeholder, sans visuel) a été ajouté pour débloquer le build
iOS — le projet le réclamait sans le fournir (cf. `Docs/DECISIONS.md` #19). Une vraie icône de marque
sera proposée à l'étape de polish.

## Récupérer ce commit dans Xcode

Le projet `Sillon.xcodeproj` existe et utilise des **groupes synchronisés au système de fichiers**
(`PBXFileSystemSynchronizedRootGroup`) : les nouveaux fichiers Swift déposés dans les dossiers sont
repris automatiquement par Xcode, sans manipulation du `.xcodeproj`. Après un `git pull`, ouvrez le
projet et **Cmd + R**.

### Capacités à vérifier côté projet Xcode

- macOS : Signing & Capabilities ▸ App Sandbox ▸ Network ▸ **Outgoing Connections (Client)**.
- Si votre serveur Jellyfin/Navidrome est en `http://` : exception App Transport Security
  (onglet Info de la target ▸ Allow Local Networking = YES / Allow Arbitrary Loads selon le cas).
- Bundle Identifier unique, aligné avec `service` dans `Security/KeychainStore.swift`.

## Et après ?

Le commit 4 (Téléchargements) enchaîne sur cette bibliothèque : `DownloadManager` en arrière-plan,
reproduction de l'arborescence serveur, lecture offline-first. Voir `Sillon/Docs/ROADMAP.md`.
