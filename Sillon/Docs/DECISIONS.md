# Décisions documentées (Phase 1)

Conformément au mode de travail demandé : pas de question bloquante pour les choix non critiques,
décision la plus standard prise et documentée ici (+ en commentaire dans le code source concerné).

1. **Subsonic — pas de dépendance externe.** Aucune librairie Swift mature et largement adoptée
   pour l'API Subsonic/OpenSubsonic n'a été identifiée (contrairement à Rust/Go). Décision :
   implémentation REST manuelle via `URLSession`, sur la base de la spécification confirmée
   (endpoints `ping`, `getArtists`, `getAlbumList2`, `stream`, `download`, `getCoverArt`,
   `search3`, `getStarred2`/`star`/`unstar`, `createPlaylist`/`updatePlaylist`/`deletePlaylist`).

2. **Jellyfin — SDK officiel non retenu pour la Phase 1.** Il existe un SDK Swift officiel
   (`jellyfin/jellyfin-sdk-swift`, généré depuis l'OpenAPI Jellyfin). Décision : implémentation
   REST manuelle minimale plutôt que ce SDK généré (volumineux), pour garder un seul target léger
   et un contrôle total sur le sous-ensemble d'endpoints réellement utilisé
   (`/Users/AuthenticateByName`, `/Users/{id}/Items`, `/Audio/{id}/stream?static=true`,
   `/Items/{id}/Images/Primary`). Le SDK officiel reste une option de bascule future,
   signalée mais pas ajoutée sans validation explicite.

3. **Favoris — propriété, pas modèle séparé.** `isFavorite` / `favoriteDate` sont portés
   directement par `Artist`, `Album`, `Track` plutôt qu'un modèle `Favorite` distinct.
   Plus simple à requêter (pas de jointure), suffisant pour les besoins de la Phase 1
   (toggle, écran "Favoris", "Mixer les favoris").

4. **"Presets EQ utilisateur" vs "pas de presets nommés".** Le brief mentionne les deux
   (section Stack vs section Fonctionnalités point 8). Interprétation retenue, la plus
   contraignante des deux : un seul état EQ persistant (singleton `EQSettings`),
   pas de presets multiples nommés. Des presets nommés pourront être proposés en Phase 2
   si souhaité.

5. **Arborescence de téléchargement, différence iOS/macOS.** Le brief décrit
   `~/Music/<NomServeur>/Artiste/Album/Piste`. Cette arborescence est appliquée littéralement
   sur **macOS** (dossier Musique de l'utilisateur, via l'entitlement sandbox dédié
   "File Access > Music Folder"). Sur **iOS**, il n'existe pas de dossier `~/Music` partagé
   accessible à une app tierce : on utilise donc le dossier *Documents* de l'app
   (visible dans l'app Fichiers si `UIFileSharingEnabled`/`LSSupportsOpeningDocumentsInPlace`
   sont activés), avec **la même arborescence relative** `<NomServeur>/Artiste/Album/Piste`.

6. **`ServerProvider` comme protocole d'acteur.** Cf. commentaire dans `ServerProvider.swift` :
   décision prise pour la sécurité de concurrence (sync, lecture et téléchargements simultanés),
   cohérente avec le mode de concurrence strict probable des nouveaux projets Xcode visant
   iOS 26 / macOS 26 (Tahoe).

7. **Livraison sous forme de fichiers sources, pas de `.xcodeproj` généré à la main.**
   Le fichier `.xcodeproj` est un format propriétaire fragile à produire sans Xcode lui-même.
   Décision : fournir les fichiers Swift organisés en dossiers (qui deviendront des groupes Xcode),
   à importer dans un nouveau projet créé depuis le gabarit Xcode "App" multiplateforme.
   Voir `README.md` pour la procédure pas à pas.

8. **Nom de projet provisoire : "Sillon".** Aucun nom n'était imposé par le brief. "Sillon"
   (le sillon du vinyle) fait écho à l'identité visuelle retenue (voir `DESIGN_SYSTEM.md`).
   Entièrement renommable sans impact technique (il s'agit du nom du module/target Xcode).

## Commit 2 — Gestion des serveurs + providers réseau

9. **En-tête d'authentification Jellyfin : `X-Emby-Authorization`, pas `Authorization`.**
   `Authorization` est un nom d'en-tête réservé par les frameworks réseau d'Apple et peut être
   intercepté/réécrit par le système dans certains contextes — un point régulièrement signalé par
   des développeurs iOS dans l'écosystème Jellyfin. `X-Emby-Authorization` est accepté par tous
   les serveurs Jellyfin et évite ce risque.

10. **Suppressions non détectées par `syncDelta`, sur les trois providers.** Ni Jellyfin
    (`MinDateLastSaved` renvoie les ajouts/modifications, pas les suppressions), ni Subsonic
    (aucun mécanisme de suppression confirmé), ni les fichiers locaux (cohérence délibérée avec
    les deux autres, bien que techniquement détectable) ne signalent les suppressions via la
    synchro delta. Cette limite est documentée plutôt que contournée par un mécanisme inventé ;
    elle sera traitée par une réconciliation complète périodique (`fetchLibrary`) au commit
    "Synchronisation + Bibliothèque".

11. **Subsonic : authentification "mot de passe" OU "jeton + sel" fixes.** Conformément au brief
    ("password/token+salt"), le formulaire propose les deux modes. En mode "jeton + sel", l'app ne
    stocke jamais le mot de passe — seulement le couple jeton/sel fourni par l'utilisateur, réutilisé
    tel quel sur chaque requête (contrairement au mode mot de passe, où un sel aléatoire frais est
    généré à chaque requête, comme recommandé par la spécification).

12. **"Test de connexion avant sauvegarde" appliqué littéralement.** Le bouton Enregistrer du
    formulaire d'ajout de serveur reste désactivé jusqu'à un test de connexion réussi ; toute
    modification d'un champ pertinent invalide ce test (évite d'enregistrer des identifiants
    jamais vérifiés, ou modifiés après le test).

13. **Ce commit ne fait pas encore apparaître de bibliothèque réelle.** Le bouton "Synchroniser"
    de l'écran Serveurs authentifie réellement le serveur et appelle `fetchLibrary`/`syncDelta`
    (preuve de bon fonctionnement de la connexion), mais ne persiste pas encore les résultats en
    SwiftData — c'est le rôle du moteur de synchronisation, prévu au commit suivant
    ("Synchronisation + Bibliothèque").

## Commit 3 — Synchronisation + Bibliothèque

14. **Playlists distantes non importées en Phase 1.** Le modèle `Playlist` est local à l'app
    (clé `UUID`, pas de `remoteID`), conformément au périmètre de Phase 1 (playlists créées/gérées
    côté app). Le moteur de synchro **ignore donc** les `RemotePlaylist` renvoyées par les providers :
    persister des playlists distantes exigerait un champ `remoteID` et une migration de schéma en
    cours de phase. La création/édition de playlists (CRUD + réordonnancement) reste le commit 6.

15. **Upsert via un index mémoire préfixé, pas une requête par élément.** `LibrarySyncService`
    charge une seule fois les modèles existants d'un serveur (filtrés par le préfixe `<serverID>:`
    de leur identifiant composite) dans un `LibraryIndex` en mémoire, puis fait les
    créations/mises à jour à partir de cet index. Évite une requête SwiftData par artiste/album/
    morceau. Limite assumée : l'index charge en mémoire les modèles du serveur concerné — acceptable
    aux volumes de Phase 1 ; une pagination pourra être introduite si nécessaire.

16. **Curseur de synchro amorcé à l'instant présent après un scan complet.** `fetchLibrary()` ne
    renvoie pas de curseur ; après une 1ʳᵉ synchro complète, on fixe `syncCursor` à l'horodatage
    ISO8601 courant (format commun aux trois providers, cf. leurs `syncDelta`) pour que la synchro
    suivante puisse fonctionner en mode delta.

17. **Artwork résolu à l'exécution, pas persisté.** Les URLs de pochette dépendent de l'état
    d'authentification (Jellyfin embarque `api_key`, Subsonic embarque jeton+sel) : on persiste
    donc le *chemin* distant (`coverArtRemotePath`) et on résout l'URL chargeable au moment de
    l'affichage via `ArtworkLoader` (cache des providers authentifiés + des URLs). Les fichiers
    locaux n'exposent pas de pochette (`coverArtURL` renvoie `nil`) → placeholder cuivré déterministe.

18. **Favoris en lecture seule à ce commit.** Les cœurs sont affichés là où `isFavorite` est vrai
    (artistes, morceaux, section "Favoris récents"), mais le *toggle* et l'écran Favoris dédié
    relèvent du commit 6 — on n'anticipe pas l'interaction ici pour respecter le découpage.

19. **Correctif de configuration : `AppIcon` manquant (pré-existant).** Le projet Xcode déclarait
    `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` sans set d'icône correspondant, ce qui faisait
    échouer **tout build iOS** (macOS tolère l'absence). Un `AppIcon.appiconset` vide (placeholder,
    sans visuel) a été ajouté pour rendre le projet compilable sur les deux plateformes. Une vraie
    icône de marque sera proposée explicitement à l'étape de polish, pas ajoutée silencieusement.

20. **Sauvegarde explicite en fin de synchro (et non via autosave seul).** `LibrarySyncService`
    appelle `context.save()` à la fin d'une synchro réussie, plutôt que de compter sur l'autosave
    du `mainContext`. Deux raisons : (a) écrire la bibliothèque durablement et immédiatement après
    un import en masse ; (b) rendre l'opération vérifiable en test sans dépendre du timing de
    l'autosave. Note de test associée : un `ModelContainer` in-memory **jetable** dont l'autosave
    asynchrone se déclenche après coup (contexte en cours de désallocation) fait planter le process
    de test — artefact propre aux tests (l'app réelle a un container à vie longue, validé sans
    crash). Les tests désactivent donc l'autosave (`autosaveEnabled = false`). Vérifié par
    `SillonTests/LibrarySyncServiceTests` (synchro complète + delta) sur SDK macOS 26.5.

## Commit 3 — validation contre serveurs réels (iOS 26)

Le commit a été validé de bout en bout sur le simulateur iOS 26.5 contre les vrais serveurs de
l'utilisateur (Jellyfin ~16 k titres, Navidrome ~16 k titres) — auth → synchro → persistance →
Accueil avec pochettes réelles. Cette campagne a fait émerger les correctifs suivants.

21. **Pagination Jellyfin + session réseau tolérante (bug réel corrigé).** `JellyfinProvider.fetchItems`
    demandait jusqu'à **5000 éléments en une seule requête** (avec `MediaStreams`) — ce qui **expirait**
    (NSURLError -1001) sur un vrai serveur domestique via internet, empêchant toute synchro d'une
    bibliothèque réelle. Corrigé par une **pagination** `StartIndex`/`Limit` (pages de 500) et une
    `URLSession` dédiée plus tolérante (`timeoutIntervalForRequest = 90 s`, `waitsForConnectivity`).
    Après correctif : synchro complète de ~16 k titres aboutie et persistée sur iOS 26.

22. **Apparence sombre imposée à l'app.** Le système de design est sombre par nature (fond noir,
    texte ivoire). L'app suivait l'apparence système : en mode clair, les titres ivoire devenaient
    illisibles sur fond blanc (constaté au test visuel). On force donc `.preferredColorScheme(.dark)`
    au niveau de l'app — **uniquement l'app**, sans toucher au réglage clair/sombre du système.

23. **Outils de test : amorçage DEBUG + tests d'intégration réseau (sans secret).** `App/DebugBootstrap.swift`
    (compilé **uniquement en DEBUG**) crée un serveur et lance une synchro si l'app est lancée avec des
    variables `SILLON_DEMO_*` — permet une validation de bout en bout sur simulateur sans saisie
    manuelle ni contrôle d'écran (`SIMCTL_CHILD_…` via `simctl launch`). `SillonTests/ServerIntegrationTests`
    fait de même côté test, en lisant les identifiants depuis l'environnement et en **se désactivant**
    s'ils sont absents. Aucun identifiant n'est codé en dur ni committé : tout vient de l'environnement
    de lancement, fourni localement.

## Commit 4 — Téléchargements

24. **Racine de téléchargement par plateforme ; `~/Music` macOS différé.** L'arborescence relative
    `<NomServeur>/<Artiste>/<Album>/<NN - Titre>.<ext>` (décision #5) est appliquée sous *Documents*
    (iOS) et *Application Support* (macOS). Le placement littéral dans `~/Music` sur macOS (prévu par
    #5) nécessite l'entitlement « Music Folder » : il est **différé** pour ne pas modifier le
    sandbox/les entitlements en cours de phase. L'arborescence relative, elle, est déjà conforme et
    vérifiée (fichiers réels écrits au bon endroit sur iOS 26).

25. **Destination encodée dans `taskDescription`, pas de changement de schéma.** Le délégué de la
    session de fond doit déplacer le fichier reçu **synchroniquement** (le temporaire est supprimé au
    retour) sans accès à SwiftData : la destination (et le `trackID`) sont donc encodés dans
    `URLSessionTask.taskDescription` à la mise en file, et survivent à une relance de l'app. Aucun
    `@Model` n'a été modifié (`DownloadTask` existait déjà depuis le commit 1) → **aucune migration**,
    la bibliothèque déjà synchronisée est préservée.

26. **URLSession de fond + réconciliation au lancement.** Conformément au brief (« en arrière-plan »),
    les téléchargements utilisent `URLSessionConfiguration.background(withIdentifier:)` avec un délégué
    non isolé qui rebascule sur le `MainActor` pour écrire en SwiftData. Au lancement, `reconcileOnLaunch`
    réassocie les tâches système vivantes et repasse en échec celles interrompues sans fichier final.
    Sur iOS, un `UIApplicationDelegateAdaptor` route le completion handler du réveil en arrière-plan.
    La lecture offline-first est préparée via `DownloadManager.localURL(for:)` (le lecteur du commit 5
    s'en servira en priorité avant de streamer).

## Commit 5 — Lecteur + Égaliseur

27. **Lecture via `AVAudioFile` (local) ; streaming = récupération-puis-lecture en Phase 1.** L'EQ
    exigé (`AVAudioUnitEQ`) impose la chaîne `AVAudioEngine` (`player → EQ → mixer`), qui lit des
    `AVAudioFile` **locaux**. Un morceau téléchargé est donc lu directement (offline-first, avec EQ) ;
    un morceau **non téléchargé** est d'abord récupéré en entier (sans transcodage : `stream?format=raw`
    / `static=true`) dans un cache temporaire, puis lu — d'où une latence au démarrage. Le vrai
    streaming réseau *gapless* avec EQ (buffers progressifs) est un raffinement de Phase 2, signalé
    plutôt qu'improvisé. Validé en lecture offline réelle sur iOS 26 (titre M4A 1411 kbps téléchargé).

28. **Égaliseur : singleton persistant appliqué en direct.** Conformément à la décision #4 (un seul
    état EQ, pas de presets nommés), l'écran Égaliseur édite l'unique `EQSettings` (6-12 bandes
    log-réparties 32 Hz–16 kHz, gains -12…+12 dB, activation). Chaque changement est sauvegardé et
    réappliqué au moteur en direct ; changer le nombre de bandes recrée l'`AVAudioUnitEQ` et le
    reconnecte dans le graphe sans interrompre la lecture (vérifié sur iOS 26). Lecture en arrière-plan
    activée (`UIBackgroundModes: audio`, `AVAudioSession` en catégorie `.playback`).

## Commit 6 — Favoris + Playlists

29. **Mini-lecteur via `tabViewBottomAccessory` (iOS 26).** La première intégration plaçait le
    mini-lecteur en `safeAreaInset(.bottom)`, qui **recouvrait la barre d'onglets** (constaté au test
    visuel). On utilise désormais le slot natif iOS 26 `tabViewBottomAccessory` (prévu pour un
    now-playing façon Apple Music) : le mini-lecteur se place proprement au-dessus des onglets, qui
    restent visibles. Repli `safeAreaInset` sur macOS. Le toggle favori est exposé partout : boutons
    cœur dans les détails artiste/album et le lecteur, et menu contextuel (`trackContextMenu`) sur les
    lignes de titre (favori + ajout à une playlist) — évite d'alourdir chaque ligne.

30. **Playlists locales (création/édition côté app), conformément au périmètre.** Le CRUD agit sur le
    modèle `Playlist` local (cf. #14 : playlists distantes non importées). Le réordonnancement
    glisser-déposer réécrit `PlaylistItem.position` de façon contiguë (`PlaylistActions.move`), testé
    par `SillonTests/PlaylistActionsTests`. Validé sur iOS 26 (création, lecture, favoris). Note de
    test : la saisie clavier synthétique sur le simulateur est peu fiable (menus d'accents) — sans
    impact sur l'app, à valider au clavier réel.

## Commit 7 — Polish & revue finale

31. **Revue finale multi-agents : corrections retenues, faux positifs écartés.** Une revue par
    dimensions (correction, concurrence, UI, lecture-seule serveur) avec vérification adversariale a
    été passée sur le code Phase 1.
    - **Confirmé** : la **lecture-seule serveur** est garantie par construction — le protocole
      `ServerProvider` ne contient aucune méthode d'écriture (pas de star/unstar/create/update/delete).
    - **Corrigé** : extension de fichier vide si `format` ne contient que des espaces
      (`DownloadFileLayout`) ; positions de playlist réindexées après suppression
      (`PlaylistActions.removeItems`) ; playlists de l'Accueil rendues navigables (`HomeView`) ; menu
      contextuel ajouté sur les titres d'une playlist (`PlaylistDetailView`) ; icône serveur passée à
      `Palette.accentCuivre` (`ServerRowView`).
    - **Écarté (faux positif)** : la « data race » signalée sur le cache de providers de
      `PlayerController` n'en est pas une — la classe est `@MainActor`, le cache est lu/écrit de façon
      synchrone sur le MainActor (sérialisé) ; la compilation en concurrence stricte le confirme.
    - **Différé (stylistique)** : remplacer systématiquement `.secondary` par `Palette.texteSourdine`
      pour le texte secondaire — `.secondary` reste idiomatique et s'adapte ; sweep optionnel de polish.
    - **Accepté tel quel** : pas de `deinit` invalidant le `Timer` du lecteur — `PlayerController` vit
      le temps de l'app (instance unique), donc pas de fuite en pratique.

## Phase 2 — Visualisation de spectre + volume (sur demande)

32. **Spectre temps réel (FFT) + style extensible ; volume au niveau mixer.** La progression autour de
    la pochette est remplacée par une **visualisation de spectre** : un tap sur `engine.mainMixerNode`
    fournit les tampons audio, une FFT (Accelerate/vDSP) en extrait des magnitudes regroupées en
    bandes log, lissées (attaque rapide/chute lente) et publiées sur le MainActor. Rendu en **cercle
    de fréquences** (`SpectrumRingView`, Canvas). **5 styles** sont implémentés (tous en couronne autour
    de la pochette) : cercle de fréquences, barres, ondulation (`closedRadialPath` lissé), cascade
    (court historique de spectres en anneaux concentriques) et oscilloscope (forme d'onde temporelle
    publiée en plus par l'analyseur). Un **sélecteur** (menu dans le lecteur, persisté `@AppStorage`)
    change de style en direct.

33. **Now Playing au niveau système.** Le `PlayerController` alimente `MPNowPlayingInfoCenter`
    (titre/artiste/album/durée/position/rate + pochette chargée en best-effort) et enregistre les
    `MPRemoteCommandCenter` (play/pause/togglePlayPause/next/previous/changePlaybackPosition), mis à
    jour à chaque chargement/play-pause/seek/fin. Les handlers rebasculent sur le MainActor. Confirmé
    par le log système `mediaremoted` sur iOS 26 (item + artwork 768px + PlaybackRate) ; le **widget
    visuel ne s'affiche pas dans le simulateur** (limite d'UI connue, comme l'AirPlay) mais fonctionne
    sur appareil réel.

## Phase 2 — Lecture audiophile (en cours)

34. **Reprise au lancement + format réel.** La session (file + index + position) est persistée en
    `UserDefaults` (sauvegarde à chaque chargement/play-pause/seek et toutes les ~8 s) et restaurée au
    lancement **en pause** (`restoreLastSession`, appelée depuis `SillonApp`). Le lecteur affiche le
    **format réellement lu** (codec · fréquence d'échantillonnage · profondeur · débit), extrait de
    l'`AVAudioFile` (fallback sur le badge du titre). À venir : gapless/crossfade (pré-planification du
    morceau suivant sur le nœud) et normalisation du volume **ReplayGain** — différée car elle nécessite
    de récupérer les tags de gain côté serveur (changement de provider + de schéma).
    La **barre de volume** agit sur `engine.mainMixerNode.outputVolume` (volume relatif de l'app, 0…1),
    testable partout (vs `MPVolumeView` matériel). La progression reste lisible via la barre/temps sous
    le titre. Validé sur iOS 26 : spectre animé en temps réel, volume fonctionnel.

35. **Lecture gapless (sans blanc entre les morceaux).** Plutôt que d'arrêter le nœud à la fin d'un
    morceau puis de recharger le suivant (ce qui crée un micro-silence), on **pré-planifie** le fichier
    suivant sur le **même `AVAudioPlayerNode`** dès que le morceau courant démarre (`scheduleNextGapless`).
    `AVAudioPlayerNode` enchaîne alors les fichiers planifiés sans interruption. Le passage au morceau
    suivant (`advanceGapless`) ne **stoppe pas** le moteur : il met simplement à jour l'index, le fichier
    courant, la durée, le format et la pochette, puis pré-planifie le morceau d'après. Comme
    `playerTime.sampleTime` court **en continu** à travers les fichiers planifiés, on mémorise
    `currentTrackStartFrame` (frame de départ du morceau courant) et `currentFileLength`, et le temps
    courant est calculé par différence (`tick`). Le `seek` réinitialise ces compteurs (`stop()` remet
    `sampleTime` à zéro) et re-planifie le suivant. Toute modification de la file (shuffle, déplacement)
    appelle `rescheduleFromCurrentPosition()` pour que le **bon** morceau suivant soit pré-planifié.
    **Garde-fous** : pré-planification uniquement si le fichier suivant est accessible et de **même
    fréquence d'échantillonnage** que le nœud (sinon repli sur le rechargement classique à la transition,
    avec son court blanc) ; désactivée en répétition « une » ; les complétions sont filtrées par
    `generation` **et** par `index` pour ignorer les planifications remplacées ou déjà dépassées.
    **Validé sur iOS 26** : transition « Les Crises de l'âme » → « Carolyne » enchaînée sans blanc, format
    réel et position correctement repris sur le nouveau morceau. À venir : crossfade (fondu enchaîné, par
    `AVAudioUnitMixer`/rampes de gain) et ReplayGain (toujours en attente des tags serveur).

36. **ReplayGain (normalisation du volume) — lecture seule, appliqué sur `player.volume`.** On LIT les
    tags de gain du serveur (jamais d'écriture). **Jellyfin** n'expose qu'un gain piste,
    `BaseItemDto.NormalizationGain` (dB, propriété racine de l'item, nullable, sans peak ni gain album —
    cf. issue jellyfin#14346). **OpenSubsonic/Navidrome** expose un sous-objet `replayGain`
    (`trackGain`/`albumGain` en dB, `trackPeak`/`albumPeak` linéaires, `baseGain` sommé aux deux gains,
    `fallbackGain` de repli) présent dès que `openSubsonic: true` (absent sur Subsonic legacy → tout nil,
    décodage tolérant). Subsonic legacy et le provider local restent neutres (champs nil).
    **Schéma** : champs `Double?` ajoutés à `Track` (track/album gain+peak, fallback) et `Album`
    (album gain+peak) ; tous **optionnels** → migration légère SwiftData implicite (pas de versionnage,
    données existantes préservées, gains nil jusqu'à la prochaine synchro). Côté Subsonic, le détail
    album fournit album-gain/peak par song : on les stocke aussi sur la piste (résolution du mode
    « album » sans charger la relation) et on les agrège sur l'`Album`.
    **Réglages** : `@AppStorage` (clés `replayGainMode`/`replayGainClipProtection`/`replayGainPreampDB`),
    **pas** un `@Model` SwiftData — ce sont 4 scalaires sans état dérivé, comme `spectrumStyle` ; on évite
    ainsi un second modèle/migration. `PlayerController` relit ces clés via `UserDefaults` à l'application.
    **Application sur `player.volume`** (gain par-source) et **non** un nœud post-mix : un nœud après le
    mixer appliquerait un seul gain aux deux morceaux qui se chevauchent pendant un futur crossfade
    (faux) ; `player.volume` est correct par-source et se généralisera au crossfade (un gain par deck).
    Le volume utilisateur reste sur `mainMixerNode.outputVolume`, l'EQ sur l'`eq` — responsabilités
    séparées. Le calcul pur (`ReplayGain.linearFactor` : sélection mode + replis album→track→fallback,
    `pow(10, dB/20)`, anti-clipping `factor ≤ 1/peak` sinon cap à 0 dB si peak inconnu) est couvert par
    `SillonTests/ReplayGainTests`. Appliqué au chargement **et** à chaque transition gapless
    (`advanceGapless`, sinon le morceau suivant garderait le gain du précédent).

37. **Crossfade (fondu enchaîné) — architecture « dual-deck », gapless préservé à l'identique.** Pour
    chevaucher deux morceaux il faut deux sources simultanées : on ajoute un **deuxième `AVAudioPlayerNode`**
    et on modélise deux **decks** (`Deck` = player + son `AVAudioMixerNode` de fondu + l'état du morceau).
    Graphe crossfade : `deckA.fadeMixer / deckB.fadeMixer → sumMixer → eq → mainMixer`. **Décision clé
    anti-régression** : aiguillage strict `if crossfadeDuration > 0`. À 0, on garde le **graphe gapless
    mono-node d'origine** (`player → eq → mainMixer`, `player` == `deckA.player`) et tout le code gapless
    (seek/shuffle/repeat/advanceGapless) **inchangé** — zéro régression. Le graphe physique n'est recâblé
    qu'au franchissement de la frontière 0↔>0.
    **Rampe equal-power** (cos/sin, `out²+in²=1`, pas de creux de -3 dB) pilotée par un timer dédié à
    60 Hz ; sa **progression est dérivée de l'horloge audio du deck entrant** (pas d'une horloge murale)
    → robuste au gel du RunLoop (arrière-plan/interruption). **Bascule atomique** de l'identité du morceau
    (index/titre/durée/`activeIsA`) au **début** du fondu : la barre de progression suit le morceau entrant,
    et la garde `index == currentIndex` de `handleTrackEnded` rejette la complétion tardive du sortant.
    **Temps courant per-deck** en crossfade (`seekFrame + sampleTime`, chaque deck étant `stop()` avant
    planification) ; le modèle gapless cumulé reste pour le mode 0.
    **Niveau** : `sumMixer` à **1.0** (un morceau seul sort au même niveau qu'en gapless) ; le fondu
    equal-power garde la puissance constante et, pour deux morceaux décorrélés, le pic de sommation reste
    ≈ unité. **Format de rendu** toujours valide (taux matériel si négocié, sinon taux du fichier — jamais
    0 Hz) ; les `fadeMixer` convertissent les fréquences hétérogènes (crossfade inter-sample-rate géré).
    **ReplayGain** par-deck : chaque `deck.player.volume` porte le gain de SON morceau (compose avec la
    rampe sur le `fadeMixer`). **Interruptions** : tout changement explicite (next/previous/jump/seek,
    shuffle/déplacement, repeat « une ») appelle `abortCrossfade()` synchrone pour figer le fondu avant la
    fenêtre `await`. **Réglage** `@AppStorage("crossfadeDuration")` (0…12 s) ; `refreshCrossfade()` recâble
    en pleine lecture au franchissement de 0↔>0 (bref rechargement accepté — action rare).
    **Revue adversariale** (5 lentilles, 8 défauts confirmés tous corrigés) puis **validé sur iOS 26** :
    fondu equal-power complet « Les Crises de l'âme » → « Carolyne » (log : `out/in` de 1/0 → 0.7/0.7 →
    0/1, puis bascule), sans crash (un crash initial dû à un `renderFormat` 0 Hz quand le moteur était
    démarré avant le câblage a été corrigé : on câble avant de démarrer, comme le gapless).

## Phase 2 — Paroles synchronisées (sur demande)

38. **Paroles à la demande, lecture seule, synchronisées.** Récupération À LA DEMANDE (jamais persistée,
    hors schéma SwiftData, hors synchro) via une nouvelle méthode du protocole `ServerProvider`
    (`func lyrics(forTrackID:) async throws -> TrackLyrics?`), comme `ArtworkLoader` : un `LyricsLoader`
    `@MainActor @Observable` (environnement, cache providers par serveur + résultats par `track.id`,
    positif ET négatif) appelé par `LyricsView(track:)` en `.task(id:)`. **APIs** : **Jellyfin**
    `GET /Audio/{id}/Lyrics` (`Lyrics[].{Text, Start}`, `Start` en ticks .NET → s = ticks/10_000_000,
    404 → nil) ; **OpenSubsonic** `getLyricsBySongId` (`structuredLyrics[].{synced, offset, line[].{start, value}}`,
    `start`/`offset` en **ms** → s = ms/1000 ; on choisit la variante synchronisée non vide parmi
    plusieurs langues) ; **Local** tags embarqués (`iTunesMetadataLyrics`/`id3MetadataUnsynchronizedLyric`,
    texte simple, lignes vides filtrées) sinon nil. Toutes les requêtes sont des **GET** — lecture seule
    confirmée par revue. Modèle `TrackLyrics { synced, lines: [LyricLine{ timeSeconds?, text }] }`.
    **UI** : bouton `quote.bubble` dans le `bottomRow` du lecteur ouvrant une **sheet** (detents
    `.medium/.large`). Si synchronisé : surlignage de la ligne courante (cuivre, plus grande) via
    `TrackLyrics.activeLineIndex(at:)` (robuste à un ordre non trié, sans réordonner l'affichage)
    lue sur `player.currentTime`, auto-défilement `ScrollViewReader` centré, tap sur une ligne = `seek`.
    Sinon texte simple défilable ; états chargement / « Pas de paroles ». Calcul/décodage couverts par
    `SillonTests/LyricsTests` (formats réels Jellyfin/Subsonic). **Validé sur iOS 26** : surlignage
    synchronisé qui avance et auto-défile (paroles synthétiques), et état vide réel sur Navidrome (dont
    les fichiers n'ont pas de paroles ; **Jellyfin en a sur ~78 % des titres**, souvent synchronisées).

## Phase 3 (sur demande)

39. **Minuterie de veille.** Le `PlayerController` arme un `Timer` (`armSleepTimer(after:)`) et publie
    `sleepTimerEndDate` (pour un éventuel décompte UI). Deux entrées : durée fixe (15/30/45/60 min,
    `setSleepTimer(minutes:)`) ou **fin du morceau** (`setSleepTimerEndOfTrack()` = temps restant
    `duration - currentTime`, ce qui marche identiquement en gapless ET en crossfade, contrairement à
    une interception de fin de piste). À l'échéance : **fondu de sortie** (~4 s, rampe du
    `mainMixerNode.outputVolume` vers 0 par pas de 0,1 s) puis pause via `togglePlayPause` (pause propre
    selon le mode), et **restauration du volume utilisateur** pour que la reprise ne soit pas muette.
    `cancelSleepTimer` invalide tout et restaure le volume. UI : un menu **lune** (`moon.zzz`) dans la
    barre du haut du lecteur (cuivre + `moon.zzz.fill` quand armé, option « Désactiver » en tête).
    Indépendant du serveur. Logique d'armement/annulation testée (`PlayerQueueTests`). **Validé sur
    iOS 26** : armement → fondu → pause à l'échéance → icône réinitialisée → volume restauré à la reprise.

40. **Radio / titres similaires — InstantMix Jellyfin, repli par genre Subsonic.** Nouvelle méthode
    lecture seule du protocole `ServerProvider` (`radioTracks(seedTrackID:limit:)`). **Jellyfin** :
    `GET /Items/{id}/InstantMix` (mix local par genres/métadonnées, décodé comme une réponse Items).
    **Subsonic** : on **n'appelle PAS** `getSimilarSongs(2)` — l'agent Last.fm peut être indisponible
    et faire **expirer** la requête (45 s observés sur le serveur de test) ; repli rapide et fiable par
    **genre** (`getSong` pour le genre de la graine → `getSongsByGenre`, mélangé, graine exclue ; sinon
    `getRandomSongs`). **Local** : titres au hasard de la bibliothèque. `PlayerController.startRadio(from:)`
    récupère ces `RemoteTrack`, les **résout dans la bibliothèque locale** (`FetchDescriptor` par id
    composite — seuls les titres déjà synchronisés sont jouables), et démarre la file (graine en tête).
    UI : « Lancer une radio » (icône `antenna.radiowaves.left.and.right`) dans le menu contextuel des
    titres. Décodage testé (`RadioTests`). **Validé sur iOS 26** contre Navidrome : file de **41 titres**
    du même genre, artistes variés (Klaus Nomi → Cabrel, Vai, ELP, Bangles, Gainsbourg, Coldplay…),
    sans aucun timeout.

41. **Navigation par genres / décennies + tri des albums.** **Schéma** : champ `Track.genre: String?`
    (optionnel → migration légère, validée live : 15 738 titres préservés, colonne ajoutée). Parsé en
    sync : Subsonic `song.genre`, Jellyfin `Genres[].first` (champ `Genres` ajouté au `Fields`).
    **Tri des albums** : `AlbumSortOrder` (titre/artiste/année/récent) ; `AlbumsGridView(sort:)` reconstruit
    son `@Query` depuis l'ordre, `LibraryRootView` tient l'état et un menu de tri (barre d'outils).
    **Parcourir** (icône `rectangle.3.group`) → `BrowseRootView` : « Par genre » (`GenresListView` —
    genres distincts via un `FetchDescriptor` à `propertiesToFetch: [\.genre]` pour ne charger que la
    colonne, dédupliqués → `GenreTracksView` filtré + « Mélanger ») et « Par décennie » (`DecadesListView`
    — décennies déduites de `Album.year`, déjà stocké, **sans migration** → `DecadeAlbumsView`).
    **Décision navigation** : on utilise des `NavigationLink` à **closure** (et non `value:` +
    `navigationDestination`) dans ces vues poussées — le `navigationDestination(for:)` placé dans une vue
    elle-même atteinte par un lien à closure ne s'enregistrait pas de façon fiable (titres non cliquables
    en test). Détail : `"\(String(decade))s"` pour éviter le séparateur de milliers ajouté par le format
    locale à un Int dans un `LocalizedStringKey`. Tests `LibraryNavigationTests` (décodage genre, ordres
    de tri). **Validé sur iOS 26** : tri par année, genres (→ titres), décennies (→ albums).

42. **Onglet « Récents » + correctif du parseur de date Subsonic.** Nouveau segment **« Récents »** dans
    la Bibliothèque (`RecentAdditionsView`) : grille d'albums triée par **date d'ajout serveur**
    (`Album.dateAdded`) avec bascule **Plus récents / Plus anciens** (segmenté), `@Query` reconstruit selon
    l'ordre. Libellé court « Récents » (et non « Ajout récent ») pour tenir dans le picker à 5 segments
    sans troncature. **Bug pré-existant corrigé** : Navidrome renvoie les dates `created` avec des
    **nanosecondes** (ex. `2026-06-24T12:28:00.382717832Z`, 9 décimales), que l'`ISO8601DateFormatter`
    standard **rejette** (il n'accepte que 0 ou 3 décimales) → `dateAdded` était **nil pour TOUS** les
    albums et titres (affectant aussi l'« Ajouts récents » de l'accueil et le tri « récent »). Helper
    `SubsonicProvider.parseDate` tolérant : essai ms, puis sans fraction, puis **troncature des fractions
    à 3 chiffres** ; appliqué aux 4 points de parsing (curseur delta, getAlbumList2, makeRemoteAlbum,
    makeRemoteTrack). Couvert par `LibraryNavigationTests`. **Validé sur iOS 26** : tri desc/asc effectif.
    Note : les dates réelles n'apparaissent qu'après une **re-synchronisation** (le cache existant avait
    été synchronisé avec l'ancien parseur).
