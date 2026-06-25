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
