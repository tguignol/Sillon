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
  **Validé sur iOS 26.5 contre les vrais serveurs Jellyfin et Navidrome (~16 k titres chacun)** :
  auth → synchro → persistance → Accueil avec pochettes réelles (cf. Docs/DECISIONS.md #21-23,
  dont la correction d'un timeout réel par pagination du provider Jellyfin).

- [x] **Commit 4 — Téléchargements** *(celui-ci)*
  `DownloadManager` (URLSession **de fond** + délégué), reproduction de l'arborescence serveur
  (`<NomServeur>/<Artiste>/<Album>/<NN - Titre>.<ext>`), file visible avec statut/progression
  (Réglages ▸ Téléchargements), boutons de téléchargement par titre et par album, réconciliation au
  lancement, helper de lecture offline-first (`localURL(for:)`).
  **Validé sur iOS 26.5** : album Navidrome (11 titres M4A 1411 kbps, ~295 Mo) téléchargé de bout en
  bout, fichiers écrits dans l'arborescence serveur, état reflété dans l'UI (cf. Docs/DECISIONS.md #24-26).

- [x] **Commit 5 — Lecteur + Égaliseur** *(celui-ci)*
  Moteur `AVAudioEngine` (`player → AVAudioUnitEQ → mixer`), `PlayerController` (file de lecture,
  transport, temps courant, offline-first), écran lecteur plein écran (pochette + *groove ring*
  signature, barre de progression avec -10s/+10s, cœur favori, sélecteur AirPlay), mini-lecteur
  ancré, écran Égaliseur (6-12 bandes log, sliders libres, activation, sauvegarde du singleton
  `EQSettings`, application en direct).
  **Validé sur iOS 26.5** : lecture **offline** d'un titre M4A téléchargé (temps qui avance, groove
  ring), changement de bandes EQ en direct (cf. Docs/DECISIONS.md #27-28).

- [x] **Commit 6 — Favoris + Playlists** *(celui-ci)*
  Toggle cœur partout (détails artiste/album, lecteur, menu contextuel sur les titres) ; onglet
  Favoris (albums + titres) avec « Mixer les favoris » (lecture aléatoire) ; CRUD playlists
  (créer/supprimer) + détail avec réordonnancement glisser-déposer (`onMove`) et ajout via
  « Ajouter à une playlist ». Mini-lecteur déplacé dans le slot natif iOS 26 `tabViewBottomAccessory`.
  **Validé sur iOS 26.5** (cf. Docs/DECISIONS.md #29-30).

- [x] **Commit 7 — Polish & revue finale Phase 1** *(celui-ci)*
  Revue multi-agents du code (correction, concurrence, UI, lecture-seule serveur) avec vérification
  adversariale ; corrections appliquées (cf. Docs/DECISIONS.md #31) ; mini-lecteur masqué quand rien
  ne joue ; README d'exécution finalisé. **Lecture-seule serveur confirmée par la revue.**
  → Phase 1 terminée. Pause pour validation avant d'attaquer la Phase 2.

## Phase 1 — terminée ✅

Les 7 commits sont faits et validés sur iOS 26.5 contre les vrais serveurs (Jellyfin + Navidrome).
Builds macOS + iOS verts, tests unitaires verts. En attente de validation avant Phase 2.

## Phase 2 (en cours, sur demande)

- [x] **Visualisation de spectre + barre de volume** *(sur demande utilisateur)*
  Analyseur de spectre temps réel (`AudioSpectrumAnalyzer` : tap audio + FFT Accelerate) ;
  visualisation **cercle de fréquences** (`SpectrumRingView`) autour de la pochette, à la place de
  l'anneau de progression ; barre de **volume** dans le lecteur (entre le transport et la ligne du
  cœur), reliée au mixer du moteur. L'enum `SpectrumStyle` prévoit les autres styles (ondulation,
  barres, cascade, oscilloscope) — le **sélecteur de style** sera ajouté plus tard.
  **Validé sur iOS 26.5** : spectre animé en temps réel + volume fonctionnel (cf. Docs/DECISIONS.md #32).

Reste de la Phase 2 (proposée) : voir la proposition de la conversation, à développer après validation.
