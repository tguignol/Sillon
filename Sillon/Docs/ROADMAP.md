# Feuille de route — Phase 1 (cœur)

Découpage en commits logiques, conformément au mode de travail demandé. Chaque commit est livré
compilable (à vérifier dans Xcode, voir limitation d'environnement dans le README) et prévisualisable.

- [x] **Commit 1 — Fondations** *(celui-ci)*
  Modèles SwiftData (ServerAccount, Artist, Album, Track, Playlist, PlaylistItem, DownloadTask,
  EQSettings), Keychain, protocole `ServerProvider` + DTOs, squelette d'app (TabView previewable),
  système de design (palette/typo), journal de décisions.

- [x] **Commit 2 — Gestion des serveurs + providers réseau** *(celui-ci)*
  `JellyfinProvider`, `SubsonicProvider`, `LocalFilesProvider` (implémentations complètes du
  protocole `ServerProvider`, endpoints vérifiés par recherche) ; écran liste des serveurs avec
  bouton "Synchroniser" (authentification + appel `fetchLibrary`/`syncDelta` réels, sans encore
  persister les résultats — cf. Docs/DECISIONS.md #13) ; formulaire d'ajout avec masques distincts
  par type et test de connexion obligatoire avant sauvegarde.

- [x] **Commit 3 — Synchronisation + Bibliothèque** *(celui-ci)*
  Moteur de sync `LibrarySyncService` (delta vs full, upsert SwiftData par id composite, horodatage
  + curseur), barre de progression réelle sur l'écran Serveurs ; système de design `Theme.swift`
  (palette/typo/espacement) ; vues Artistes/Albums/Titres/Playlists (+ détails artiste/album) ;
  écran d'accueil avec sections horizontales à tailles inégales (Ajouts récents, Favoris récents,
  Playlists) ; chargement d'artwork réel (`ArtworkLoader`) avec fallback placeholder cuivré.
  Affichage des favoris en lecture seule (le toggle arrive au commit 6).

- [ ] **Commit 4 — Téléchargements**
  `DownloadManager` (URLSessionDownloadTask en arrière-plan), reproduction de l'arborescence
  serveur, file visible avec statut, lecture offline-first.

- [ ] **Commit 5 — Lecteur + Égaliseur**
  Moteur AVAudioEngine/AVAudioUnitEQ, écran lecteur (cover plein écran, barre de progression avec
  -10s/+10s, cœur favori, sélecteur de sortie audio AirPlay/Bluetooth), écran Réglages EQ
  (6-12 bandes, sliders libres, sauvegarde du dernier état).

- [ ] **Commit 6 — Favoris + Playlists**
  Toggle cœur partout, écran Favoris + "Mixer les favoris", CRUD playlists + réordonnancement
  par glisser-déposer.

- [ ] **Commit 7 — Polish & revue finale Phase 1**
  Cohérence visuelle inter-écrans, vérification des Previews, README d'exécution finalisé.
  → Pause pour validation avant d'attaquer la Phase 2.

## Phase 2 (proposée, non développée)

Voir la proposition donnée dans la conversation. À ne développer qu'après validation explicite.
