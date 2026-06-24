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

## Hors-commit — Réglages projet (à refaire si le projet est recréé)

14. **App Transport Security : `NSAllowsArbitraryLoads = YES`.** Réglage à ajouter dans l'onglet
    Info de la target Xcode (pas un fichier source — ne survit pas à une recréation du projet).
    Choisi plutôt qu'une exception de domaine ciblée (`NSExceptionDomains`) car les serveurs
    personnels visés par l'app (IP locale, nom DDNS de box opérateur, etc.) changent d'un serveur
    à l'autre et sont presque toujours en `http://` ou en certificat auto-signé. Acceptable pour
    une app qui ne parle qu'à des serveurs choisis par l'utilisateur lui-même ; à revoir si l'app
    est un jour distribuée sur l'App Store (Apple demande alors une justification).
