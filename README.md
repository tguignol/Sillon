# Sillon — Commit 2/7 de la Phase 1

App de lecture musicale connectée à des serveurs personnels (Jellyfin, Navidrome/Subsonic,
fichiers locaux), SwiftUI multiplateforme (iOS 26 / macOS Tahoe), target unique.

Ce commit ajoute la **gestion des serveurs** et les **trois providers réseau** par-dessus les
fondations du commit 1 (toujours présentes). Voir `Docs/ROADMAP.md` pour la suite.

## Contenu ajouté par ce commit

```
Networking/
  ServerProviderFactory.swift     → instancie le bon provider selon ServerAccount.type
  Jellyfin/JellyfinModels.swift   → DTOs (BaseItemDto, AuthenticationResult...)
  Jellyfin/JellyfinProvider.swift → authenticate, fetchLibrary, syncDelta, streamURL...
  Subsonic/SubsonicModels.swift   → DTOs (enveloppe subsonic-response...)
  Subsonic/SubsonicProvider.swift → idem, pour Navidrome/Subsonic
  Local/LocalFilesProvider.swift  → scan de dossier + métadonnées AVFoundation
Views/Servers/
  ServerListView.swift            → liste des serveurs, bouton Synchroniser
  ServerRowView.swift
  AddServerView.swift             → formulaire d'ajout, masques distincts par type
Views/Settings/
  SettingsRootView.swift          → racine de l'onglet Réglages (-> Serveurs)
ViewModels/
  ServerListViewModel.swift
  AddServerViewModel.swift
```

**Important** : ce commit ne fait pas encore apparaître de vraie bibliothèque musicale dans
l'onglet Bibliothèque. Le bouton "Synchroniser" authentifie réellement le serveur et récupère
sa bibliothèque, mais ne persiste pas encore le résultat en SwiftData — c'est le rôle du moteur
de synchronisation, prévu au commit suivant. Voir `Docs/DECISIONS.md` (#13) pour le détail.

## Limitation importante à connaître avant de continuer

Je travaille dans un environnement Linux sans Xcode ni toolchain Swift : **je ne peux pas
compiler, lancer, ni générer de Previews moi-même**. Le code a été écrit avec soin et vérifié
contre la documentation officielle (notamment les endpoints Jellyfin/Subsonic, confirmés par
recherche plutôt qu'inventés), mais la première compilation réelle se fera dans votre Xcode.
**Si vous rencontrez une erreur de build, copiez-collez le message d'erreur ici** — je corrige
immédiatement plutôt que de deviner.

## Ce dépôt ne contient pas (encore) de fichier de projet Xcode

Volontairement : un fichier `.xcodeproj` est un format propre à Xcode, fragile à produire sans
Xcode lui-même, donc je ne le fabrique pas à la main. Ce dépôt contient les **fichiers source
Swift et la documentation** — la création du projet Xcode autour de ces fichiers se fait une
fois, en local, en suivant la procédure ci-dessous.

## Démarrer depuis ce dépôt GitHub (nouvelle procédure)

1. **Cloner ce dépôt avec Xcode** : Xcode → écran d'accueil → **Clone an existing project** (ou
   menu **File ▸ Clone Repository…**) → collez `https://github.com/tguignol/Sillon.git` → choisissez
   où l'enregistrer sur votre Mac (évitez un dossier synchronisé par iCloud du type "Documents",
   préférez par exemple un dossier directement sous votre dossier utilisateur, ou `~/Developer/`,
   pour éviter les soucis de synchronisation qui semblent être à l'origine du problème précédent).
2. **Créer le projet Xcode à cet endroit précis** : File ▸ New ▸ Project ▸ onglet **Multiplatform**
   ▸ **App** (Interface SwiftUI, Storage SwiftData) ▸ Product Name `Sillon` ▸ **enregistrez-le
   dans le dossier que vous venez de cloner** (pas un nouveau dossier ailleurs).
3. Xcode crée ses fichiers par défaut à côté des fichiers déjà clonés. Supprimez les fichiers
   générés par défaut (`Item.swift`, contenu par défaut de `ContentView.swift`) — `App/SillonApp.swift`
   et `App/RootTabView.swift` (déjà présents grâce au clone) les remplacent.
4. Dans Xcode, clic droit sur le groupe racine du projet → **Add Files to "Sillon"…** → sélectionnez
   les dossiers déjà présents sur le disque (`Models`, `Networking`, `Security`, `Persistence`,
   `Views`, `ViewModels`, `App` s'il n'est pas déjà ajouté) → **décochez "Copy items if needed"**
   cette fois (les fichiers sont déjà au bon endroit, pas besoin d'une copie) → cochez **Create
   groups** et votre target.
5. **Cmd + R**.

### Capacités à vérifier (cf. détail plus bas dans ce fichier)

- macOS : Signing & Capabilities ▸ App Sandbox ▸ Network ▸ **Outgoing Connections (Client)**.
- Si votre serveur Jellyfin/Navidrome est en `http://` : exception App Transport Security
  (onglet Info de la target ▸ Allow Local Networking = YES).
- Bundle Identifier unique, aligné avec `service` dans `Security/KeychainStore.swift`.

## Pour la suite (Commit 3 et après)

Désormais, je pousse directement mes commits sur ce dépôt GitHub (sous forme de pull requests,
que vous validez avant de les fusionner sur `main`). Une fois une pull request acceptée, vous
récupérez les nouveaux fichiers dans Xcode via **Source Control ▸ Pull…** — plus besoin de zips
ni de copier-coller manuel.

## Et après ?

Dites-moi quand le projet compile chez vous après cette procédure, ou collez-moi le message
d'erreur exact si quelque chose bloque.
