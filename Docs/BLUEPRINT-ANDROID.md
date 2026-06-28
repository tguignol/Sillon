# Blueprint de portage Android — Sillon

**Cible** : application Android native **Kotlin + Jetpack Compose**, visuellement et fonctionnellement **quasi identique** à l'app iOS/iPadOS/macOS SwiftUI existante. Optimisée pour le **Samsung Galaxy Z Fold 7** (UI adaptative pliable).

Ce document cartographie l'app iOS existante et donne, sous-système par sous-système, les correspondances Android recommandées. Il sert de plan de référence pour le portage.


---

# Design system & thème

Aucune police custom embarquée (`UIAppFonts` absent) : l'app utilise uniquement les polices système (`Font.system(design: .serif/.monospaced/.default)`). J'ai tout le nécessaire pour produire la documentation.

## Design System Sillon — Référence pour le portage Android (Compose)

Source unique : `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/DesignSystem/Theme.swift`. Tout est versionné **en code** (pas de `Color set` dans `Assets.xcassets` — seul `AccentColor.colorset` existe mais n'est pas utilisé par la palette). **Apparence par défaut = mode sombre** ; les valeurs `dark` reproduisent à l'identique la palette d'origine.

Tension de design fondatrice : **chaleur cuivrée** pour la musique / le cover art ; **froid technique** (monospace + teal) réservé aux données (bitrate, codec, dB, horodatages de sync).

### Palette (`enum Palette`)

| Token | Rôle | Hex clair | Hex sombre |
|---|---|---|---|
| `fondNoir` | Fond principal | `#F6F4EF` | `#0B0D0F` |
| `surfaceElevee` | Cartes, feuilles modales, lignes survolées | `#FFFFFF` | `#15181B` |
| `accentCuivre` | Accent principal (cœur favori, lecture en cours, AccentColor) | `#B06D2C` | `#D98E4A` |
| `signalTeal` | Données techniques (EQ actif, sync, badges codec) | `#2E7D75` | `#4FA8A0` |
| `texteIvoire` | Texte principal | `#1C1A17` | `#F3F1EC` |
| `texteSourdine` | Texte secondaire, légendes, métadonnées | `#6E6A64` | `#9A9590` |

Mécanique iOS : `Color(light:dark:)` résout dynamiquement via `UITraitCollection` / `NSAppearance` selon l'apparence effective. Opacité toujours 1.0, espace sRGB. Le helper `Color(hex: 0xRRGGBB)` décompose en `r/g/b` divisés par 255.

### Typographie (`enum Typo`)

**Aucune police custom embarquée** (pas de `UIAppFonts`). Tout est `Font.system(...)` :
- `design: .serif` → **New York** (police serif système Apple)
- `design: .monospaced` → **SF Mono**
- `design: .default` → **SF Pro**

Les tailles ne sont **pas** des points fixes mais des **text styles dynamiques** (Dynamic Type) — il faut donc mapper vers les tailles de base des text styles iOS au gabarit par défaut (`.large`).

| Token | Famille | Text style iOS (taille base pt) | Poids | Usage |
|---|---|---|---|---|
| `display` | SERIF (New York) | `.title` (28) | regular | Titres d'album, nom d'artiste en grand |
| `displaySmall` | SERIF (New York) | `.title3` (20) | `.medium` (500) | Sous-titres serif |
| `paroleActive` | SERIF (New York) | `.title2` (22) | `.semibold` (600) | Ligne de paroles EN COURS (un cran au-dessus des autres, façon Apple Music) |
| `corps` | DÉFAUT (SF Pro) | `.body` (17) | regular | Corps / UI général |
| `technique` | MONOSPACE (SF Mono) | `.caption` (12) | regular | Donnée technique : bitrate, codec, dB, horodatage sync |

### Espacement (`enum Spacing`)

| Token | Valeur (CGFloat) |
|---|---|
| `xs` | 4 |
| `s` | 8 |
| `m` | 12 |
| `l` | 16 |
| `xl` | 24 |
| `xxl` | 32 |
| `cardCorner` (rayon d'angle cartes/pochettes/sections) | 10 |

### Dégradé placeholder déterministe (`Palette.placeholderGradient(seed:)`)

Pochettes manquantes (fichiers locaux, serveur sans cover art). **Déterministe** : un même album garde TOUJOURS la même couleur entre lancements.

- Hash **djb2** stable (PAS `hashValue`, randomisé par process) :
  `stableHash = seed.unicodeScalars.reduce(5381) { ($0 &* 33) &+ $1.value }` (UInt64, overflow autorisé)
- `hue = Double(stableHash % 360) / 360.0`
- Couleur `base` : `Color(hue: hue, saturation: 0.28, brightness: 0.34)` (HSB)
- Couleur `dark` : `Color(hue: hue, saturation: 0.35, brightness: 0.18)` (HSB)
- `LinearGradient(colors: [base, dark], startPoint: .topLeading, endPoint: .bottomTrailing)` → diagonale haut-gauche → bas-droite.

### Modificateur de vue réutilisable

`View.techniqueData()` → `font(Typo.technique)` + `foregroundStyle(Palette.signalTeal)`. À reproduire comme un style de texte composable unique (police monospace caption + couleur teal).

---

## Correspondance Compose

### Couleurs (`ui/theme/Color.kt`)

```kotlin
// Clair
val FondNoirLight      = Color(0xFFF6F4EF)
val SurfaceEleveeLight = Color(0xFFFFFFFF)
val AccentCuivreLight  = Color(0xFFB06D2C)
val SignalTealLight    = Color(0xFF2E7D75)
val TexteIvoireLight   = Color(0xFF1C1A17)
val TexteSourdineLight = Color(0xFF6E6A64)

// Sombre (= rendu d'origine, apparence par défaut)
val FondNoirDark       = Color(0xFF0B0D0F)
val SurfaceEleveeDark  = Color(0xFF15181B)
val AccentCuivreDark   = Color(0xFFD98E4A)
val SignalTealDark     = Color(0xFF4FA8A0)
val TexteIvoireDark    = Color(0xFFF3F1EC)
val TexteSourdineDark  = Color(0xFF9A9590)
```

Mapping vers `darkColorScheme()` / `lightColorScheme()` Material 3 :
- `background` = FondNoir, `surface` = FondNoir, `surfaceVariant`/cartes = SurfaceElevee
- `primary` = AccentCuivre, `onBackground`/`onSurface` = TexteIvoire
- `secondary`/`tertiary` = SignalTeal (réserver strictement aux données techniques, pas l'UI générale)
- texte secondaire = TexteSourdine (via un slot custom ou `onSurfaceVariant`)

Bascule clair/sombre pilotée par l'équivalent de `AppearanceMode` (systeme/clair/sombre → `isSystemInDarkTheme()` / forcé), à exposer dans les réglages.

### Typographie (`FontFamily` + `Typography`)

Les polices serif/mono système d'Apple (New York, SF Mono) **ne sont pas sur Android** : il faut **embarquer des polices équivalentes** dans `res/font/` pour matcher le rendu iOS.

| Token iOS | FontFamily Compose | Police à embarquer (match visuel iOS) | `fontSize` (sp) | `FontWeight` |
|---|---|---|---|---|
| `display` | `SillonSerif` | **Source Serif 4** (ou Newsreader / Lora) ≈ New York | 28 | `Normal` |
| `displaySmall` | `SillonSerif` | idem | 20 | `Medium` (500) |
| `paroleActive` | `SillonSerif` | idem | 22 | `SemiBold` (600) |
| `corps` | `FontFamily.Default` (Roboto) | — police système | 17 | `Normal` |
| `technique` | `FontFamily.Monospace` | **JetBrains Mono** ou Roboto Mono ≈ SF Mono | 12 | `Normal` |

Recommandation police serif : **Source Serif 4** (SIL OFL, libre, gabarit le plus proche de New York) ou **Newsreader**. Embarquer regular/medium/semibold dans `res/font/` et déclarer :

```kotlin
val SillonSerif = FontFamily(
    Font(R.font.source_serif_regular, FontWeight.Normal),
    Font(R.font.source_serif_medium,  FontWeight.Medium),
    Font(R.font.source_serif_semibold, FontWeight.SemiBold),
)
```

Important : iOS utilise du **Dynamic Type** ; côté Compose, garder les tailles en **sp** (pas dp) pour respecter l'accessibilité, et idéalement mapper sur `MaterialTheme.typography` plutôt que des littéraux dispersés.

### Espacements et formes (`ui/theme/Dimens.kt` / `Shape.kt`)

```kotlin
object Spacing {
    val xs = 4.dp; val s = 8.dp; val m = 12.dp
    val l = 16.dp; val xl = 24.dp; val xxl = 32.dp
}
val CardCorner = 10.dp
// Shapes Material 3 : medium = RoundedCornerShape(10.dp) pour cartes/pochettes/sections
```

dp ↔ CGFloat à l'identique (1:1) — les valeurs iOS sont en points, donc reprises telles quelles en dp.

### Dégradé placeholder déterministe (à reproduire fidèlement)

```kotlin
fun placeholderBrush(seed: String): Brush {
    var hash = 5381UL
    for (c in seed) hash = hash * 33UL + c.code.toULong()   // djb2, overflow ULong OK
    val hue = (hash % 360UL).toFloat()                       // 0..359
    val base = Color.hsv(hue, 0.28f, 0.34f)
    val dark = Color.hsv(hue, 0.35f, 0.18f)
    return Brush.linearGradient(listOf(base, dark))          // défaut ≈ topLeft → bottomRight
}
```

Notes de fidélité :
- Itérer sur les **unicode scalars** (en Kotlin, attention aux caractères hors BMP / surrogates ; `seed.codePoints()` reproduit exactement `unicodeScalars` d'iOS). Pour des seeds ASCII (IDs d'album), `for (c in seed)` suffit.
- `Color.hsv(hue, sat, val)` Compose attend `hue` en **degrés 0–360** (≠ iOS `Color(hue:)` qui prend 0–1). Donc passer `hue` brut (0–359), ne PAS le diviser par 360.
- `Brush.linearGradient(colors)` sans `start`/`end` part en diagonale top-left → bottom-right comme `.topLeading → .bottomTrailing`.

### Modificateur réutilisable `techniqueData`

```kotlin
@Composable
fun techniqueTextStyle() = MaterialTheme.typography.labelSmall.copy(
    fontFamily = FontFamily.Monospace,
    color = SignalTeal,        // résolu clair/sombre via le thème
)
```

Reproduit `View.techniqueData()` (monospace caption + teal), à appliquer sur tout affichage de donnée technique (codec, bitrate, dB, horodatage de sync).

### Fichier à porter
- Source iOS unique : `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/DesignSystem/Theme.swift` (147 lignes — palette, Typo, Spacing, helpers `Color(hex:)` / `Color(light:dark:)`, `AppearanceMode`).
- Côté Android : éclater en `Color.kt`, `Type.kt`, `Dimens.kt`, `Shape.kt`, `Theme.kt` + assets `res/font/` (serif + mono à embarquer).

---

# Architecture & navigation adaptative

J'ai toutes les informations nécessaires. Voici la documentation.

## Navigation & point d'entrée — État iOS et portage Android

### 1. Point d'entrée et cycle de vie

**iOS** — `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/App/SillonApp.swift`
- `@main struct SillonApp: App` avec une unique `WindowGroup { RootTabView() }` et `.modelContainer(modelContainer)` (SwiftData).
- `init()` exécute, dans l'ordre : `LanguageManager.bootstrap()` (redirige `Bundle.main` vers la langue choisie avant tout texte), `SillonSchema.makeContainer()`, puis instancie `DownloadManager` et `PlayerController` (qui dépend de `downloadManager` et `container`).
- `.task` au lancement : `downloadManager.reconcileOnLaunch()` + `playerController.restoreLastSession()`.
- AppDelegate via `@UIApplicationDelegateAdaptor(SillonAppDelegate.self)` (iOS) / `@NSApplicationDelegateAdaptor(SillonMacAppDelegate.self)` (macOS).

**AppDelegate** — `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/App/SillonAppDelegate.swift`
- iOS : `application(_:handleEventsForBackgroundURLSession:completionHandler:)` route le completion handler du réveil en arrière-plan vers `DownloadManager.shared?.backgroundCompletionHandler`.
- macOS : `applicationShouldTerminateAfterLastWindowClosed → true` (fermer la fenêtre quitte l'app, la lecture ne continue pas en fond).

**Réglages globaux appliqués à la racine** (`SillonApp.body`) :
- `.preferredColorScheme(appearance.colorScheme)` — `@AppStorage("appearanceMode")`, défaut `.sombre`.
- `.environment(\.locale, …)` + `.id(languageRaw)` — change de langue en forçant la **reconstruction complète** de l'arbre (re-traduction de tous les textes). `@AppStorage(LanguageManager.storageKey)`.

→ **Android** : `Application` (Hilt `@HiltAndroidApp`) + une seule `MainActivity` (`ComponentActivity` + `setContent { SillonTheme { RootScaffold() } }`). Remplacer l'AppDelegate background-URLSession par **WorkManager** (`DownloadWorker` avec contrainte réseau) ; le routage du completion handler n'a pas d'équivalent (WorkManager gère la reprise). Apparence = `MaterialTheme(colorScheme = if (dark) darkColorScheme else lightColorScheme)` piloté par DataStore. Changement de langue = `AppCompatDelegate.setApplicationLocales(LocaleListCompat…)` (per-app language, API 33+ / AppCompat 1.6) — pas besoin du hack `.id()` car la recréation d'Activity relit les ressources. Le `restoreLastSession`/`reconcileOnLaunch` → `LaunchedEffect(Unit)` dans le composable racine ou init du ViewModel de session.

---

### 2. Modèle de navigation adaptatif

**iOS** — `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/App/RootTabView.swift`

Logique de bascule (exacte) :
```
#if os(iOS)
  if UIDevice.current.userInterfaceIdiom == .pad {
      GeometryReader { geo in
          if geo.size.width > geo.size.height { SidebarRootView() }  // iPad paysage
          else { tabRoot }                                           // iPad portrait
      }
  } else { tabRoot }                                                 // iPhone : toujours onglets
#else
  SidebarRootView()                                                  // macOS : toujours barre latérale
#endif
```
- **Onglets** (iPhone + iPad portrait) : `TabView` avec mini-lecteur ancré via `tabViewBottomAccessory` (slot natif iOS 26, modifieur `NowPlayingAccessory` qui n'affiche la capsule que si `hasNowPlaying`), et `PlayerView` plein écran via `.fullScreenCover(isPresented: $showPlayer)`.
- **Barre latérale** (iPad paysage + macOS) : `SidebarRootView` (`/Users/thomaskohler/_DEV/Github/Sillon/Sillon/App/SidebarRootView.swift`) = `NavigationSplitView`. Colonne latérale = `List(selection:)` sur `SidebarSection.allCases` ; largeur `min: 172, ideal: 196, max: 240`. Zone de détail : soit `PlayerView(onClose:)` **en ligne** (la barre reste visible, pas une feuille), soit la section courante avec `NowPlayingBar` ancré via `.safeAreaInset(edge: .bottom)` sur fond `.thinMaterial`. `onChange(of: selection)` referme le lecteur ; animation `.easeInOut(duration: 0.2)`.
- Critère clé : la bascule se fait sur **largeur > hauteur** (GeometryReader), pas sur une classe de taille.

→ **Android — reproduire l'adaptatif, y compris pliable (Z Fold 7)** :
- Utiliser **`NavigationSuiteScaffold`** (Material3 adaptive, `androidx.compose.material3.adaptive:adaptive-navigation-suite`) : il choisit automatiquement `NavigationBar` (bas) vs `NavigationRail` vs `PermanentNavigationDrawer` selon la `WindowSizeClass`.
- Calculer la `WindowSizeClass` via `currentWindowAdaptiveInfo()` (`material3-adaptive`). **Mais** la règle Sillon est « largeur > hauteur », pas une simple breakpoint : surcharger le `navigationSuiteType` manuellement —
  ```kotlin
  val info = currentWindowAdaptiveInfo()
  val w = info.windowSizeClass.windowWidthSizeClass
  val landscapeOrWide = w >= WindowWidthSizeClass.MEDIUM // ≈ iPad paysage / écran déplié
  val type = if (landscapeOrWide) NavigationSuiteType.NavigationDrawer
             else NavigationSuiteType.NavigationBar
  ```
- **Pliable (Z Fold 7)** : ajouter **Jetpack WindowManager** (`androidx.window:window` + `WindowInfoTracker`). Observer `windowLayoutInfo` pour les `FoldingFeature` :
  - **Plié** (cover screen, ~6.5", étroit) → `NavigationBar` (onglets bas), équivalent iPhone.
  - **Déplié** (~8", quasi carré, large) → `NavigationDrawer`/`PermanentDrawer`, équivalent iPad paysage / barre latérale.
  - Gérer `FoldingFeature.State.HALF_OPENED` + `Orientation` pour un éventuel mode table/livre (TwoPane via `androidx.compose.material3.adaptive:adaptive-layout` `ListDetailPaneScaffold`). Le `material3-adaptive` consomme déjà `WindowLayoutInfo` (postures) en interne, donc privilégier `currentWindowAdaptiveInfo().windowPosture` plutôt que recoder WindowManager à la main, sauf pour la règle « width > height ».
- Le **NavigationSplitView détail-en-ligne** (lecteur affiché dans la colonne de détail sans masquer la liste) → `ListDetailPaneScaffold` ou un `Row { NavigationDrawer; content }` où le « détail » alterne entre la section et l'écran Lecteur via un état `showPlayer`. Le mini-lecteur ancré bas = `Scaffold(bottomBar = { if (hasNowPlaying) NowPlayingBar() })` ; en mode onglets c'est un composable au-dessus de la `NavigationBar`.
- Plein écran lecteur (mode onglets) = destination de navigation dédiée (`NavHost` route `player`) ou `ModalBottomSheet`/full-screen `Dialog` — équivalent `fullScreenCover`.

---

### 3. Inventaire des sections / écrans

**Sections racines** (5, identiques onglets ⇄ barre latérale — `RootTabView.tabRoot` et `SidebarRootView.SidebarSection`) :

| Section | Vue racine | Icône SF Symbol | Route Android (Material Icons proche) |
|---|---|---|---|
| Accueil | `HomeView` | `house.fill` | `Icons.Filled.Home` |
| Bibliothèque | `LibraryRootView` | `music.note.list` | `Icons.Filled.LibraryMusic` |
| Favoris | `FavoritesView` | `heart.fill` | `Icons.Filled.Favorite` |
| Recherche | `SearchView` | `magnifyingglass` | `Icons.Filled.Search` |
| Réglages | `SettingsRootView` | `gearshape.fill` | `Icons.Filled.Settings` |

**Accueil** (`/Views/Home/HomeView.swift`) : `NavigationStack` + empilement de carrousels horizontaux (albums récents, favoris, à redécouvrir, écoute en cours, titres préférés, albums aléatoires, playlists). Sélections aléatoires figées par lancement. `albumCardSize = 160`. État vide `LibraryEmptyState`. → Android : `LazyColumn` de `LazyRow` (carrousels), card 160.dp.

**Bibliothèque** (`/Views/Library/LibraryRootView.swift`) : `NavigationStack` + `Picker(.segmented)` à 5 sections (`enum Section`: `.ajoutRecent="Récents"`, `.artistes`, `.albums`, `.titres`, `.playlists`, défaut `.albums`). `.searchable` (prompt « Artistes, albums, titres ») → bascule sur `SearchResultsView`. Toolbar : menu de tri albums (`AlbumSortOrder`, icône `arrow.up.arrow.down`) + lien `BrowseRootView` (icône `rectangle.3.group`). Sous-vues : `ArtistsListView`, `AlbumsGridView(sort:)`, `TracksListView`, `PlaylistsListView`, `RecentAdditionsView`. → Android : `SegmentedButton` (Material3) ou `TabRow` + `SearchBar` ; tri = `DropdownMenu`.

**Favoris** : `FavoritesView`. **Recherche** : `SearchView` + `SearchResultsView`. **Playlists** : `PlaylistsListView`, `PlaylistDetailView`, `AddToPlaylistView`.

**Réglages** (`/Views/Settings/SettingsRootView.swift`) : `NavigationStack` + `List` :
- Apparence — `Picker(.menu)` sur `AppearanceMode`, icône `circle.lefthalf.filled`.
- Langue — `Picker` (`.navigationLink` iOS / `.menu` macOS) sur `AppLanguage` (11 entrées), icône `globe` ; applique `LanguageManager.apply()` avant maj du `@AppStorage`.
- Serveurs → `ServerListView` (`server.rack`) — `AddServerView`, `ServerRowView`.
- Téléchargements → `DownloadsView` (`arrow.down.circle`).
- Égaliseur → `EQView` (`slider.vertical.3`).
- Lecture → `PlaybackSettingsView` (`play.circle`).

**Lecteur** (`/Views/Player/`) : `PlayerView` (plein écran ou colonne détail), `NowPlayingBar` (mini-lecteur), `EQView`.

→ **Android navigation interne** : un `NavHost` (Navigation-Compose) par onglet (back stacks indépendantes par destination racine, comme les `NavigationStack` distincts d'iOS) ; `SettingsRootView` → écran de préférences avec lignes cliquables vers sous-routes. Les `navigationDestination` partagés de la Bibliothèque (les 4 sous-vues partagent une même `NavigationStack`) → un seul `NavHost` avec routes `artist/{id}`, `album/{id}`, etc.

---

### 4. Injection de dépendances (`@Environment`)

iOS injecte 5 dépendances partagées à la racine (`SillonApp.body`), via `@Entry`/`EnvironmentKey`, consommées par `@Environment(\.…)` :

| Clé environnement | Type | Défini dans | Rôle |
|---|---|---|---|
| `\.artworkLoader` | `ArtworkLoader` (non-optionnel, `@Entry`) | `/Views/Shared/ArtworkLoader.swift:71` | Cache pochettes (providers authentifiés + URLs résolues) |
| `\.lyricsLoader` | `LyricsLoader` (`@Entry`) | `/Views/Shared/LyricsLoader.swift:41` | Paroles à la demande, lecture seule, cache/morceau |
| `\.downloadManager` | `DownloadManager?` (`@Entry`, défaut `nil`) | `/Downloads/DownloadManager.swift:248` | Téléchargements (URLSession de fond) |
| `\.playerController` | `PlayerController?` (`@Entry`, défaut `nil`) | `/Player/PlayerController.swift:1326` | Moteur AVAudioEngine + EQ, file de lecture |
| `\.hasMultipleServers` | `Bool` (`EnvironmentKey`, défaut `false`) | `/Views/Shared/SourceBadge.swift:68` | Calculé `servers.filter(\.isActive).count > 1` ; pilote pastilles source + déduplication |

`PlayerController` et `DownloadManager` sont des `@Observable` créés en `init()` et stockés en `@State` ; `hasMultipleServers` est dérivé d'un `@Query [ServerAccount]` dans `RootTabView`. Le `modelContext` SwiftData est aussi injecté (`.modelContainer`).

→ **Android (Hilt recommandé)** :
- `ArtworkLoader` → **Coil** `ImageLoader` (singleton `@Provides`), avec `OkHttpClient` portant l'auth serveur (intercepteur). C'est l'équivalent direct du cache providers/URLs.
- `LyricsLoader`, `DownloadManager`, `PlayerController` → singletons Hilt (`@Singleton @Provides` ou `@Inject`), exposés aux composables via un `ViewModel` (`hiltViewModel()`) ou `CompositionLocal` pour les loaders légers. `PlayerController` → wrapper autour de **Media3 ExoPlayer** + `MediaSessionService` (lecture en fond, contrôles notification/Android Auto) ; remplace AVAudioEngine ; l'EQ → `androidx.media3` `Equalizer`/`AudioProcessor`.
- `DownloadManager` → Media3 `DownloadManager` (`androidx.media3:media3-exoplayer-dash`/`-hls`) + WorkManager pour la reprise/contraintes, en injection Hilt singleton.
- `\.hasMultipleServers` (Bool dérivé) → `StateFlow<Boolean>` exposé par un `ServersRepository` (`servers.filter { it.isActive }.size > 1`), collecté via `collectAsStateWithLifecycle()` ; pas besoin de CompositionLocal, le passer en paramètre ou via ViewModel partagé.
- `modelContainer` SwiftData → **Room** `Database` (singleton Hilt) ; les `@Query` deviennent des DAO `Flow<List<…>>`.
- Équivalent du `CompositionLocal` SwiftUI = `staticCompositionLocalOf {}` / `compositionLocalOf {}` pour les loaders globaux légers (artwork/lyrics), mais privilégier l'injection Hilt + ViewModel pour les contrôleurs avec état (player, downloads) afin de survivre aux recréations d'Activity (rotation, dépliage du Fold).

---

**Constantes de design réutilisées** (`/DesignSystem/Theme.swift:77` `enum Spacing`) : `xs=4, s=8, m=12, l=16, xl=24` → mapper directement en `dp` Android (`object Spacing { val xs = 4.dp … }`).

**Fichiers clés** :
- `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/App/SillonApp.swift`
- `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/App/RootTabView.swift`
- `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/App/SidebarRootView.swift`
- `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/App/SillonAppDelegate.swift`
- `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Views/Library/LibraryRootView.swift`
- `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Views/Settings/SettingsRootView.swift`
- `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Views/Shared/{ArtworkLoader,LyricsLoader,SourceBadge}.swift`, `/Player/PlayerController.swift`, `/Downloads/DownloadManager.swift`

---

# Réseau, fournisseurs & modèles

J'ai maintenant tous les éléments. Voici la documentation.

## Couche réseau Sillon — Architecture et portage Android (Ktor + kotlinx.serialization)

### Vue d'ensemble

| Fichier iOS | Rôle | Équivalent Android |
|---|---|---|
| `Networking/ServerProvider.swift` | Protocole commun (acteur) | `interface ServerProvider` (suspend funs) |
| `Networking/ProviderModels.swift` | DTOs `Sendable` + erreurs | `data class` Kotlin + `sealed class ProviderException` |
| `Networking/ServerProviderFactory.swift` | Fabrique selon type serveur | `object ServerProviderFactory` |
| `Networking/Jellyfin/*` | Provider + DTOs Jellyfin | `JellyfinProvider` + `@Serializable` |
| `Networking/Subsonic/*` | Provider + DTOs Subsonic | `SubsonicProvider` + `@Serializable` |
| `Networking/Local/LocalFilesProvider.swift` | Dossier local (SAF sur Android) | `LocalFilesProvider` |
| `Sync/LibrarySyncService.swift` | Moteur upsert vers SwiftData | `LibrarySyncService` vers Room |
| `Library/Deduplication.swift` | Dédup d'affichage multi-serveurs | extensions/helpers Kotlin |
| `Favorites/Favoritable.swift` | Propagation favori entre copies | interface `Favoritable` |

---

### 1. Protocole `ServerProvider`

Déclaré `protocol ServerProvider: Actor` (acteur Swift pour la sécurité de concurrence : chaque provider porte un état mutable — jeton de session, cache). Toutes les méthodes sont `async throws`.

| Méthode Swift | Signature | Rôle |
|---|---|---|
| `authenticate()` | `-> ProviderSession` | Auth, renvoie jeton/version. Pour `.local` : résout le bookmark, pas de réseau |
| `fetchLibrary()` | `-> LibrarySnapshot` | Scan complet (1ère synchro uniquement) |
| `syncDelta(since:)` | `(String?) -> SyncDelta` | Synchro incrémentale depuis curseur ; lève une erreur si `since == nil` |
| `streamURL(for:)` | `(String) -> URL` | URL de lecture, format original sans transcodage |
| `downloadURL(for:)` | `(String) -> URL` | URL de téléchargement complet (peut différer de `streamURL`) |
| `coverArtURL(for:preferredSize:)` | `(String, Int?) -> URL?` | URL de pochette, taille demandée si supportée |
| `searchAll(query:)` | `(String) -> SearchResults` | Recherche unifiée artistes+albums+titres |
| `lyrics(forTrackID:)` | `(String) -> TrackLyrics?` | Paroles à la demande ; `nil` = pas de paroles (cas normal, pas une erreur) |
| `radioTracks(seedTrackID:limit:)` | `(String, Int) -> [RemoteTrack]` | Titres apparentés (InstantMix Jellyfin / genre Subsonic) ; peut renvoyer `[]` |
| `serverFavorites()` | `-> RemoteFavorites` | IDs favoris côté serveur (LECTURE SEULE, jamais d'écriture) |

**Équivalent Android** — pas d'acteur natif ; utiliser un `interface` avec fonctions `suspend` et confiner l'état mutable via un `Mutex` (kotlinx.coroutines) ou un dispatcher mono-thread :

```kotlin
interface ServerProvider {
    suspend fun authenticate(): ProviderSession
    suspend fun fetchLibrary(): LibrarySnapshot
    suspend fun syncDelta(since: String?): SyncDelta
    suspend fun streamUrl(trackRemoteId: String): String   // String/HttpUrl plutôt que java.net.URL
    suspend fun downloadUrl(trackRemoteId: String): String
    suspend fun coverArtUrl(remoteId: String, preferredSize: Int?): String?
    suspend fun searchAll(query: String): SearchResults
    suspend fun lyrics(trackRemoteId: String): TrackLyrics?
    suspend fun radioTracks(seedTrackId: String, limit: Int): List<RemoteTrack>
    suspend fun serverFavorites(): RemoteFavorites
}
```

---

### 2. Modèles / DTOs (`ProviderModels.swift`)

DTOs `Sendable` volontairement détachés des modèles persistés (SwiftData → Room). Champs exacts :

**`ProviderSession`** : `serverDisplayName: String?`, `serverVersion: String?`, `userID: String?`, `token: String?` (l'appelant stocke le jeton ; le provider ne touche jamais au Keychain).

**`RemoteArtist`** : `id: String` (remoteID sans préfixe serveur), `name: String`, `sortName: String?`, `coverArtPath: String?`.

**`RemoteAlbum`** : `id`, `artistID: String?`, `artistName: String?`, `title`, `year: Int?`, `coverArtPath: String?`, `dateAdded: Date?`, `albumGain: Double? = nil`, `albumPeak: Double? = nil` (ReplayGain, OpenSubsonic seulement).

**`RemoteTrack`** : `id`, `albumID: String?`, `albumTitle: String?`, `artistName: String?`, `title`, `trackNumber: Int?`, `discNumber: Int?`, `durationSeconds: Double`, `format: String?`, `bitrate: Int?`, `dateAdded: Date?`, `genre: String? = nil`, `trackGain/trackPeak/albumGain/albumPeak/fallbackGain: Double? = nil`. (Jellyfin ne renseigne que `trackGain` ; OpenSubsonic renseigne tout.)

**`RemotePlaylist`** : `id`, `name`, `trackIDs: [String]`.

**`LibrarySnapshot`** : `artists/albums/tracks: [...]`, `playlists: [RemotePlaylist]`.

**`SyncDelta`** : `updatedArtists/updatedAlbums/updatedTracks/updatedPlaylists`, `deletedTrackIDs/deletedAlbumIDs/deletedArtistIDs: [String]`, `newSyncCursor: String?`. (Les `deleted*` sont toujours vides actuellement — voir §7.)

**`SearchResults`** : `artists/albums/tracks`.

**`RemoteFavorites`** : `albumIDs/trackIDs/artistIDs: Set<String> = []`, `isEmpty: Bool`, `static let empty`.

**`LyricLine`** : `timeSeconds: Double?` (nil = non synchronisé), `text: String`.

**`TrackLyrics`** : `synced: Bool`, `lines: [LyricLine]` + méthode `activeLineIndex(at t: TimeInterval) -> Int?` (ligne horodatée de temps max ≤ t ; robuste à un ordre non trié).

**`ProviderError`** (enum `LocalizedError`) : `.invalidURL`, `.unauthorized`, `.unreachable(underlying:)`, `.unexpectedResponse(statusCode:body:)`, `.decodingFailed(underlying:)`, `.unsupportedServerVersion(String)`, `.missingCredentials`, `.cancelled`.

**Équivalent Android** :
```kotlin
@Serializable data class RemoteTrack(
    val id: String,
    val albumId: String? = null,
    val albumTitle: String? = null,
    val artistName: String? = null,
    val title: String,
    val trackNumber: Int? = null,
    val discNumber: Int? = null,
    val durationSeconds: Double,
    val format: String? = null,
    val bitrate: Int? = null,
    val dateAdded: Instant? = null,        // kotlinx-datetime
    val genre: String? = null,
    val trackGain: Double? = null, val trackPeak: Double? = null,
    val albumGain: Double? = null, val albumPeak: Double? = null,
    val fallbackGain: Double? = null,
)
data class RemoteFavorites(
    val albumIds: Set<String> = emptySet(),
    val trackIds: Set<String> = emptySet(),
    val artistIds: Set<String> = emptySet(),
) { val isEmpty get() = albumIds.isEmpty() && trackIds.isEmpty() && artistIds.isEmpty() }

sealed class ProviderException(msg: String? = null) : Exception(msg) {
    object InvalidUrl : ProviderException()
    object Unauthorized : ProviderException()
    data class Unreachable(val cause: Throwable) : ProviderException()
    data class UnexpectedResponse(val statusCode: Int, val body: String?) : ProviderException()
    data class DecodingFailed(val cause: Throwable) : ProviderException()
    data class UnsupportedServerVersion(val version: String) : ProviderException()
    object MissingCredentials : ProviderException()
    object Cancelled : ProviderException()
}
```
Note : ces DTOs `RemoteTrack/RemoteAlbum/...` sont des modèles internes, pas la forme des réponses HTTP. Ils sont construits par mapping depuis les DTOs Jellyfin/Subsonic (ci-dessous), donc ils n'ont pas besoin de `@Serializable` ; je l'indique seulement si vous les cachez sur disque.

---

### 3. Jellyfin (`JellyfinProvider.swift` / `JellyfinModels.swift`)

**Constantes** : `clientName = "Sillon"`, `clientVersion = "1.0"`, `deviceID` = UUID persisté dans `UserDefaults` sous la clé `"app.sillon.jellyfin.deviceID"` (sur Android : `SharedPreferences`/DataStore). Jeton + userID mis en cache en mémoire (`cachedToken`, `cachedUserID`).

**Base URL** : `baseURL.appending(path: "...")` — chemins relatifs ajoutés à l'URL serveur. `URLSession` custom : `timeoutIntervalForRequest = 90 s`, `timeoutIntervalForResource = 600 s`, `waitsForConnectivity = true` (serveurs auto-hébergés lents).

**En-tête d'authentification** — `X-Emby-Authorization` (et **pas** `Authorization`, réservé/réécrit par les frameworks Apple) :
```
MediaBrowser Client="Sillon", Device="Sillon", DeviceId="<deviceID>", Version="1.0"[, Token="<token>"]
```
Le `Token=` n'est ajouté qu'une fois authentifié.

**Endpoints réellement appelés** :

| Endpoint | Méthode | Paramètres | Usage |
|---|---|---|---|
| `Users/AuthenticateByName` | POST | body JSON `{"Username","Pw"}`, `Content-Type: application/json` | Auth → renvoie `AccessToken` + `User.Id` |
| `System/Info/Public` | GET | — | Version serveur (best-effort, n'échoue pas l'auth) |
| `Users/{userID}/Items` | GET | `Recursive=true`, `IncludeItemTypes=<MusicArtist\|MusicAlbum\|Audio\|Playlist>`, `Fields=DateCreated,MediaStreams,SortName,NormalizationGain,Genres,Path`, `SortBy=SortName`, `StartIndex`, `Limit=500` | Bibliothèque, paginée 500/page |
| `Playlists/{id}/Items` | GET | `UserId` | IDs des titres d'une playlist |
| `Audio/{id}/stream` | GET | `static=true`, `api_key=<token>` | Lecture + téléchargement (même URL ; pas d'endpoint download distinct) |
| `Items/{id}/Images/Primary` | GET | `maxWidth=<size>` (opt.), `api_key` | Pochette |
| `Audio/{id}/Lyrics` | GET | en-tête auth | Paroles (404 = pas de paroles → `nil`) |
| `Items/{seedID}/InstantMix` | GET | `UserId`, `Limit`, `Fields=DateCreated,MediaStreams,SortName,Path` | Radio |

**Delta** : `syncDelta` ajoute `MinDateLastSaved=<curseur>` aux 4 requêtes `/Items`. Curseur = `ISO8601DateFormatter().string(from: .now)` capturé **avant** le fetch. Jellyfin n'expose pas de suppressions à ce niveau → `deleted*` toujours vides.

**Favoris** : mêmes requêtes `/Items` avec `Filters=IsFavorite` (GET pur, lecture seule).

**Recherche** : `/Items` avec `SearchTerm=<query>`.

**Ré-auth sur 401** : `performWithReauth(_:)` — si statut 401, vide `cachedToken/cachedUserID`, ré-authentifie, reconstruit l'en-tête avec le jeton frais et retente **une** fois. Jamais utilisé sur la requête d'auth elle-même (anti-boucle).

**DTOs Jellyfin** (`Decodable`, sous-ensemble OpenAPI) :
- `JellyfinAuthenticationResult { User{ Id, Name? }, AccessToken }`
- `JellyfinPublicSystemInfo { ServerName?, Version? }`
- `JellyfinBaseItem { Id, Name?, SortName?, AlbumId?, Album?, ArtistItems[{Name?,Id?}]?, AlbumArtist?, ProductionYear?, IndexNumber? (=n° piste), ParentIndexNumber? (=n° disque), RunTimeTicks: Int64? (ticks .NET, 1 tick=100ns → s = ticks/10_000_000), DateCreated? (ISO8601), MediaStreams[{Type→StreamType, Codec, BitRate}]?, ImageTags{Primary?}?, Genres[String]?, Container?, Path?, NormalizationGain: Double? }`
- `JellyfinItemsResponse { Items, TotalRecordCount? }`
- `JellyfinLyricsResponse { Lyrics[{Text?, Start: Int64?}]? }` — `Start` en ticks .NET → secondes = `Start / 10_000_000`.

**Logique de mapping notable** (à reproduire à l'identique) :
- `fileFormat` : privilégie `Container` (1er élément avant `,`), repli sur extension de `Path`, puis codec ; pour conteneurs MP4 (`m4a,m4b,mp4,mp4a,mka,mov`) désambiguïse via le codec (`alac` vs `aac`).
- `audioBitRate` : `MediaStreams` audio `.BitRate / 1000` (Jellyfin en bits/s → kbps).
- `durationSeconds` : `RunTimeTicks / 10_000_000`.
- `coverArtPath` d'un artiste/album = l'`Id` de l'item lui-même (seulement si `ImageTags.Primary != nil`).
- `parseDate` : tente ISO8601 avec fractions puis sans ; renvoie `nil` à l'échec.

**Mapping JSON Android** : pour `StreamType` (clé JSON `"Type"`) utiliser `@SerialName("Type")`. La majorité des clés Jellyfin sont en PascalCase → soit annoter chaque champ `@SerialName`, soit ne **pas** utiliser de `namingStrategy` et déclarer les propriétés Kotlin telles quelles. `RunTimeTicks` → `Long`. Configurer `Json { ignoreUnknownKeys = true }` (équivalent du « Decodable ignore les champs non déclarés »).

---

### 4. Subsonic / OpenSubsonic (`SubsonicProvider.swift` / `SubsonicModels.swift`)

**Pas de session** : chaque requête porte ses propres paramètres d'auth ; aucun état caché. `apiVersion = "1.16.1"`, `clientName = "Sillon"`.

**Auth jeton + sel** — `makeAuthenticatedURL(path:extraQuery:)` ajoute à chaque URL :
`u=<username>`, `t=<token>`, `s=<salt>`, `v=1.16.1`, `c=Sillon`, `f=json`. Path final = `rest/<path>.view`.
Deux modes :
- **Mot de passe** : sel aléatoire par requête (`UUID sans tirets, minuscule`), `t = MD5(password + salt)` en hexadécimal minuscule (`Insecure.MD5` de CryptoKit — MD5 imposé par le protocole Subsonic).
- **Jeton + sel fixes** : couple stocké dans le Keychain (`apiToken` + `subsonicSalt`), réutilisé tel quel (l'app ne connaît pas le mot de passe en clair).

**Validation des réponses** : enveloppe `subsonic-response` ; `status == "ok"` requis. Codes 40/41/42 (identifiants invalides / jeton expiré / auth jeton non supportée) → `ProviderError.unauthorized`.

**Endpoints** (tous en `rest/<path>.view`, GET) :

| Path | Paramètres | Usage |
|---|---|---|
| `ping` | — | Auth (renvoie `version`) |
| `getArtists` | — | Artistes (`artists.index[].artist[]`) |
| `getAlbumList2` | `type=alphabeticalByArtist\|newest`, `size=500`, `offset` | Liste d'albums paginée |
| `getAlbum` | `id` | Détail album → `song[]` (avec ReplayGain) |
| `getPlaylists` / `getPlaylist` | `id` | Playlists et leurs `entry[]` |
| `search3` | `query` | Recherche (`searchResult3{artist,album,song}`) |
| `stream` | `id`, `format=raw` (sans transcodage, ≥1.9.0) | Lecture |
| `download` | `id` | Téléchargement (endpoint distinct garanti sans transcodage) |
| `getCoverArt` | `id`, `size` (opt.) | Pochette |
| `getLyricsBySongId` | `id` | Paroles (extension OpenSubsonic) |
| `getSong` | `id` | Graine radio (lire le genre) |
| `getSongsByGenre` | `genre`, `count` | Radio par genre |
| `getRandomSongs` | `size` | Radio si pas de genre |
| `getStarred2` | — | Favoris (`starred2{artist,album,song}`) |

**Delta** : `getAlbumList2?type=newest` (tri date d'ajout décroissante) ; s'arrête au 1er album dont `created <= curseur`. Pas de suppressions/renommages → réconciliation complète périodique via `fetchLibrary`.

**Radio** : évite `getSimilarSongs` (agent Last.fm lent/indisponible) ; repli genre, sinon aléatoire ; exclut la graine, mélange, prend `limit`.

**DTOs Subsonic** (`Decodable`, tous optionnels dans un body unique) :
- `SubsonicResponseEnvelope { subsonic-response → subsonicResponse }`
- `SubsonicResponseBody { status, version?, error{code,message}?, artists?, albumList2?, album?, searchResult3?, playlists?, playlist?, lyricsList?, song?, songsByGenre?, randomSongs?, starred2? }`
- `SubsonicSong { id, title, album?, albumId?, artist?, track?, discNumber?, duration? (secondes, entier), suffix? (=format), bitRate?, created?, genre?, replayGain? }`
- `SubsonicAlbum { id, name, artist?, artistId?, coverArt?, year?, created? }`
- `SubsonicReplayGain { trackGain?, albumGain?, trackPeak?, albumPeak?, baseGain?, fallbackGain? }` (cœur OpenSubsonic, absent → nil si Subsonic legacy)
- `SubsonicLyricsList { structuredLyrics[{synced?, offset? (ms), line[{start? (ms), value?}]?}]? }`

**Mapping notable** :
- ReplayGain piste : `trackGain = sum(rg.trackGain, rg.baseGain)`, `albumGain = sum(rg.albumGain, rg.baseGain)` ; `sum` propage `nil` (si gain principal absent → `nil` pour basculer sur fallback).
- Albums : ReplayGain album agrégé depuis le 1er `song` du détail qui porte `albumGain`.
- Paroles : on choisit la variante synchronisée non vide, sinon la 1ère non vide, sinon la 1ère ; `timeSeconds = start/1000 + offset/1000`.
- `parseDate` tolère les fractions de seconde à précision arbitraire (Navidrome renvoie des nanosecondes, ex. `2026-06-24T12:28:00.382717832Z`) : essaie ms, sans fraction, puis tronque à 3 décimales.

**Android** : `Json { ignoreUnknownKeys = true }`. Clé `"subsonic-response"` → `@SerialName("subsonic-response")`. MD5 : `MessageDigest.getInstance("MD5")` (pas besoin de lib). Construire l'URL via `HttpUrl.Builder` (OkHttp) ou `URLBuilder` (Ktor) pour l'encodage des query params. Pour le parse de date nanoseconde, écrire un parseur tolérant (kotlinx-datetime `Instant.parse` gère les fractions arbitraires en ISO-8601, ce qui simplifie par rapport à iOS).

---

### 5. Fichiers locaux (`LocalFilesProvider.swift`)

Pas de réseau. `authenticate()` résout un bookmark de sécurité (security-scoped sur macOS, standard sur iOS). Extensions supportées : `mp3, m4a, flac, alac, wav, aiff, aif, ogg`. Le `remoteID` d'un titre = **chemin du fichier**. IDs synthétiques : artiste `"local-artist:<nom>"`, album `"local-album:<artiste>/<album>"`. Métadonnées via AVFoundation (`commonMetadata` : title/artist/album/year + durée). Repli sur l'arborescence `Artiste/Album/Piste` quand les tags manquent. Cache (snapshot + signature chemin→date de modif) pour éviter de relire les métadonnées à chaque recherche/radio. `coverArtURL` renvoie `nil` (extraction non implémentée). Favoris : `.empty`. Paroles : tags embarqués USLT/iTunes (`©lyr`), texte simple non synchronisé.

**Android** : utiliser le **Storage Access Framework** (`ACTION_OPEN_DOCUMENT_TREE` → URI persistant via `takePersistableUriPermission`) au lieu du bookmark. Énumération via `DocumentFile`/`ContentResolver`. Métadonnées via `MediaMetadataRetriever` (équivalent AVFoundation : `METADATA_KEY_TITLE/ARTIST/ALBUM/DURATION`). Le `remoteID` devient l'URI du document.

---

### 6. Fabrique (`ServerProviderFactory.swift`)

`switch server.type` : `.jellyfin`/`.subsonic` exigent un `baseURL` non nil (sinon `ProviderError.invalidURL`), `.local` reçoit le bookmark.

```kotlin
object ServerProviderFactory {
    fun make(server: ServerAccount, http: HttpClient, creds: CredentialStore): ServerProvider =
        when (server.type) {
            ServerType.JELLYFIN -> JellyfinProvider(server.id, requireUrl(server), server.username, http, creds)
            ServerType.SUBSONIC -> SubsonicProvider(server.id, requireUrl(server), server.username, http, creds)
            ServerType.LOCAL    -> LocalFilesProvider(server.id, server.localFolderUri, context)
        }
}
```

---

### 7. Moteur de synchro (`Sync/LibrarySyncService.swift`)

`@MainActor enum` : tout le travail SwiftData sur le main actor, les appels réseau `await`és sur les acteurs provider. Stratégie : 1ère synchro (`!hasCompletedInitialSync`, c.-à-d. `lastFullSyncDate == nil`) → `fetchLibrary()` ; sinon `syncDelta(since: syncCursor)`. `Progress` avec phases `authenticating / fetchingLibrary / fetchingDelta / applying / fetchingArtwork / done`. Upsert par `remoteID` via un `LibraryIndex` en mémoire (charge tous les modèles du serveur, filtre par préfixe `<serverID>:`, enrichi au fil des insertions). Préchargement des pochettes en cache disque par lots concurrents de 8. Suppressions appliquées si fournies (titres d'abord pour éviter les orphelins) — mais les providers n'en signalent pas aujourd'hui.

**Android** : remplacer SwiftData par **Room** ; faire les upserts dans un `@Transaction` du DAO sur `Dispatchers.IO` ; remonter `Progress` via un `Flow`. Cache pochettes : Coil avec disk cache, ou un cache disque maison alimenté ici. Le préchargement concurrent = `coroutineScope { ... }` + `Semaphore(8)` ou `chunked(8).map { async {...} }`.

---

### 8. Multi-serveurs : activation, déduplication, favoris

**`ServerAccount`** (`Models/ServerAccount.swift`) — champs clés : `id: UUID`, `name`, `type: ServerType`, `baseURLString`, `username`, `isActive: Bool = true` (désactiver masque sans supprimer, réactivation sans re-synchro), `sortOrder: Int = 0` (priorité réordonnable, plus petit = préféré), `localFolderBookmark: Data?`, `syncCursor: String?`, `lastFullSyncDate/lastDeltaSyncDate`. Aucun secret stocké ici (Keychain only). `ServerType.dedupRank` : local=0, jellyfin=1, subsonic=2.

**Clés d'identité** (`Library/Deduplication.swift`, `enum DedupKey`) — aucune écriture en base, dédup d'affichage uniquement :
- `normalize(s)` : minuscule, sans diacritiques ni ponctuation, espaces compactés.
- album = `"<title>|<artist>|<year ?? 0>"` (l'année évite de fusionner des rééditions).
- track base = `"<title>|<artist>"` (sans album ni n° de piste : divergent entre serveurs) ; durée comparée à **±2 s** de tolérance.
- artist = `normalize(name)`.
- `rank(server)` = tuple `(sortOrder, type.dedupRank, createdAt)` — départage la copie gagnante.

**Déduplication** (extensions sur `[Album]/[Artist]/[Track]`, paramètre `merge: Bool`) :
- `dedupedAlbums(merge:)` → `[(album, sourceCount)]` : groupe par clé, représentant = copie de rang min, préserve l'ordre d'apparition (donc le tri du `@Query`).
- `dedupedArtists(merge:)` : représentant = copie avec le **plus d'albums liés** (Jellyfin ne peuple pas toujours la relation artiste→album), puis rang serveur.
- `dedupedTracks(merge:)` : buckets par (titre|artiste), fusion des durées proches (±2 s), garde le rang min.

**Badge source** (`Views/Shared/SourceBadge.swift`) : `SourceBadge(type:)` affiche le logo du serveur ; `SourceCountBadge(count:)` affiche « N sources » pour un élément dédupliqué. N'apparaît que via `EnvironmentValues.hasMultipleServers` (≥ 2 serveurs **actifs**).

**Propagation de favori** (`Favorites/Favoritable.swift` + `DuplicateResolver`) :
- `protocol Favoritable { isFavorite, favoriteDate }` sur `Artist/Album/Track`.
- `Favorites.setFavorite(_:on:context:)` applique l'état à l'élément **et à toutes ses copies** sur d'autres serveurs (via `DuplicateResolver.*Copies(caseInsensitive: true)`), pour que le favori survive à un changement de priorité serveur.
- `DuplicateResolver` : pré-filtre SwiftData par titre/nom (exact, ou `localizedStandardContains` si `caseInsensitive`), puis resserre via `DedupKey`. Garde-fou identité : si l'album n'a ni artiste ni année (clé non discriminante), ou le track/artiste pas d'artiste/nom, on ne propage qu'à l'élément lui-même.
- **Favoris serveur → local** (`LibrarySyncService.applyServerFavorites`) : UNION stricte — on ne fait que poser `isFavorite = true` + `favoriteDate = .now`, jamais retirer, jamais réécrire sur le serveur. Un favori serveur dont l'élément n'est pas encore synchronisé localement est ignoré (rattrapé plus tard).

**Android** : `ServerAccount` = entité Room. Les helpers de dédup deviennent des fonctions Kotlin pures sur `List<Album>/List<Track>/List<Artist>` (logique strictement reproductible — réutiliser `±2 s`, les mêmes clés, le même tri par `(sortOrder, dedupRank, createdAt)`). Pour `DuplicateResolver`, le pré-filtre SwiftData `localizedStandardContains` → requête Room `LIKE` insensible à la casse (`COLLATE NOCASE`) ou filtrage en mémoire après normalisation Unicode (`Normalizer.normalize(..., NFD)` + suppression des marques diacritiques pour reproduire `folding(.diacriticInsensitive)`). `hasMultipleServers` = `StateFlow` dérivé du nombre de serveurs actifs.

---

### Fichiers de référence (chemins absolus)

- `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Networking/ServerProvider.swift`
- `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Networking/ProviderModels.swift`
- `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Networking/ServerProviderFactory.swift`
- `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Networking/Jellyfin/JellyfinProvider.swift`
- `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Networking/Jellyfin/JellyfinModels.swift`
- `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Networking/Subsonic/SubsonicProvider.swift`
- `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Networking/Subsonic/SubsonicModels.swift`
- `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Networking/Local/LocalFilesProvider.swift`
- `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Sync/LibrarySyncService.swift`
- `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Library/Deduplication.swift`
- `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Favorites/Favoritable.swift`
- `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Models/{Track,Album,Artist,ServerAccount}.swift`
- `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Views/Shared/SourceBadge.swift`

---

# Lecteur & moteur audio

J'ai maintenant toutes les valeurs exactes. Voici la documentation.

---

## Moteur audio Sillon (iOS) → équivalents Android (Media3/ExoPlayer)

Source : `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Player/` — pièce maîtresse `PlayerController.swift` (1329 lignes, `@MainActor @Observable final class`). Chaîne de nœuds iOS : `player(s) → [fadeMixers → sumMixer] → eq (AVAudioUnitEQ) → mainMixer (volume) → output`, avec un *tap* FFT sur le `mainMixerNode`.

### Tableau d'état exposé à l'UI (à reproduire à l'identique)
| Propriété iOS | Type | Équivalent Android |
|---|---|---|
| `queue: [Track]`, `currentIndex`, `isPlaying`, `isLoading`, `currentTime`, `duration`, `errorMessage` | `@Observable` | `StateFlow`/`MutableState` dans un `ViewModel`, ou écoute de `Player.Listener` (`onIsPlayingChanged`, `onMediaItemTransition`, `onPlaybackStateChanged`) + `player.currentPosition`/`duration` |
| `spectrum: [Float]` (48 bandes, 0…1) | visualisation pochette | calcul FFT custom (voir Spectre) |
| `waveform: [Float]` (128 pts, -1…1) | oscilloscope | mêmes buffers PCM |
| `currentFormatDescription` ("FLAC · 88,2 kHz · 24 bit · 1024 kbps"), `currentQualityBadge` ("FLAC · 88,2 kHz") | `Tracks`/`Format` de Media3 (`format.sampleRate`, `format.pcmEncoding`, `format.bitrate`, `format.sampleMimeType`) |
| `audioOutput: AudioOutput?` (transport + device + sampleRate + **codec**) | `AudioManager.getDevices()` / `AudioDeviceCallback` ; codec BT via `BluetoothCodecConfig` |
| `volume: Float` (0…1) → `engine.mainMixerNode.outputVolume` | `player.volume = v` (ExoPlayer) |
| `sleepTimerEndDate: Date?` | timer applicatif (voir Veille) |
| `RepeatMode {off, all, one}`, `isShuffled` | `player.repeatMode` (`REPEAT_MODE_OFF/ALL/ONE`), `player.shuffleModeEnabled` |

---

### 1. Moteur de lecture (AVAudioEngine)

**iOS.** `AVAudioEngine` + `AVAudioPlayerNode` (deux instances pour le crossfade). Lecture via `AVAudioFile(forReading:)` — **offline-first** : `resolveURL(for:)` lit le fichier local téléchargé si présent, sinon télécharge **le flux entier** dans un cache temp (`FileManager.temporaryDirectory/SillonStreamCache`) **avant** de démarrer (latence assumée, "Phase 1" — pas de vrai streaming réseau). Serveur `.local` → chemin de fichier direct. Position lue depuis l'horloge audio : `player.playerTime(forNodeTime:).sampleTime`.

**Android recommandé.** `androidx.media3:media3-exoplayer` (+ `media3-exoplayer-flac` ou décodeur FLAC natif intégré depuis Media3 1.2). ExoPlayer gère nativement le **streaming progressif/adaptatif** — ne PAS recopier le pattern "télécharger en entier d'abord" : utiliser `ProgressiveMediaSource` + `CacheDataSource` (`SimpleCache` + `CacheDataSource.Factory`) pour cache disque automatique et lecture pendant téléchargement. Fichier local → `MediaItem.fromUri(file://...)`. Position : `player.currentPosition`. C'est un **gain net** côté Android : latence de démarrage supprimée, plus besoin de `cacheURL`/`URLSession.download`.

---

### 2. Égaliseur (AVAudioUnitEQ)

**iOS.** `AVAudioUnitEQ(numberOfBands:)`, bandes toujours `.parametric`. Géométrie dans `EQBands.swift` :
- **Bandes** : `6…12`, **défaut 8** (`EQSettings.bandCount`).
- **Fréquences centrales** : réparties log entre **32 Hz et 16 kHz** : `freq[i] = 2^(log2(32) + step·i)`.
- **Gain** : **-12…+12 dB** (`minGainDB/maxGainDB`), borné ; `band.gain`, `globalGain = 0`.
- **Largeur** : octaves, bornée `0.05…5.0`, défaut `1.0` ; `band.bandwidth`.
- **3 modes d'édition** (`EQMode`, fichier `Models/EQSettings.swift`) : `normal` (gain seul, freq/largeur figées), `parametric` (freq+largeur+gain par bande), `graphic` (courbe à poignées). L'EQ **appliqué** est toujours paramétrique ; seul l'UI diffère.
- `eq.bypass = !settings.isEnabled`. Persistance SwiftData **singleton** (`EQSettings.singletonID = 0000…0001`), pas de presets nommés.
- `refreshEQ()` reconstruit l'unité si `bandCount` change (`rebuildEQ` recâble le graphe selon mode gapless/crossfade).

**Android recommandé.** Deux options, le choix est le **point de friction n°1 pour la fidélité** :
- **Simple, fidèle au comportement système** : `android.media.audiofx.Equalizer` attaché à l'`audioSessionId` d'ExoPlayer (`exoPlayer.audioSessionId`). MAIS : nombre de bandes **imposé par le device** (souvent 5), fréquences centrales **fixées par le hardware** — impossible de garantir 6…12 bandes à 32 Hz…16 kHz, ni les modes paramétrique/graphique. Inacceptable pour une parité visuelle/fonctionnelle.
- **Fidèle, recommandé ici** : EQ paramétrique **custom** via `androidx.media3.common.audio.AudioProcessor` (chaîne de biquads / peaking filters DSP que tu implémentes, un par bande, mêmes fréquences log 32 Hz–16 kHz, gain ±12 dB, Q dérivé de la largeur en octaves) inséré avec `DefaultAudioSink.Builder().setAudioProcessors(...)` (ou `RenderersFactory` custom). C'est ce qui reproduit fidèlement `EQBands`. Coût : écrire le DSP biquad (cookbook RBJ) toi-même.

---

### 3. ReplayGain (`ReplayGain.swift` + `ReplayGainMode.swift`)

**iOS.** Calcul pur testable `ReplayGain.linearFactor(...)`. Appliqué **par source** sur `player.volume` (deckA/deckB), PAS post-mix → survit au crossfade (chaque deck porte son gain).
- **Modes** (`ReplayGainMode`) : `.off` (→ facteur 1.0), `.track` (égalise piste à piste), `.album` (gain commun album).
- **Replis** (jamais cumulés) : album → `albumGain` → `albumRelGain` (relation Album) → `trackGain` → `fallbackGain` ; track → `trackGain` → `fallbackGain`.
- **Gain/peak du MÊME niveau** : l'anti-clipping borne le gain avec le peak associé.
- **Pré-ampli** : `replayGainPreampDB`, plage UI **-6…+6 dB** pas 1.
- **Anti-clipping** (`replayGainClipProtection`, défaut **true**) : peak connu (>0) → `factor ≤ 1/peak` ; peak inconnu (Jellyfin) → `factor ≤ 1.0` (jamais d'amplification).
- Formule : `factor = pow(10, (baseDB + preampDB)/20)`.
- Clés `@AppStorage` lues par le contrôleur via `UserDefaults` : `replayGainMode`, `replayGainClipProtection` (object → distingue absent/false), `replayGainPreampDB`.

**Android recommandé.** Le **calcul est portable tel quel en Kotlin** (fonction pure, copie directe). Application du facteur linéaire : NE PAS utiliser `player.volume` (global, pas par-piste et écrase le volume utilisateur). Préférer un **`AudioProcessor` de gain** dans la chaîne (multiplie les samples par le facteur), réglé à chaque transition de piste via `Player.Listener.onMediaItemTransition` / `onTracksChanged`. Tags ReplayGain : extraits côté serveur (déjà dans `Track`/`Album`) — récupérer `trackGain/trackPeak/albumGain/albumPeak/fallbackGain` via le provider Subsonic/Jellyfin comme sur iOS. Persistance via `DataStore`/`SharedPreferences` (mêmes clés). Le volume utilisateur reste sur `player.volume`, le gain RG sur le processor → responsabilités séparées comme en iOS.

---

### 4. Gapless + Crossfade (deux decks)

**iOS — gapless (crossfade = 0).** Graphe mono-node `player → eq → mainMixer`. `scheduleNextGapless` **pré-planifie** le fichier suivant sur le MÊME `AVAudioPlayerNode` (`scheduleFile`) **uniquement si même sample-rate**, sinon repli au rechargement à la transition. `advanceGapless` bascule l'identité sans arrêter le moteur. Mémorise `currentTrackStartFrame`/`currentFileLength` car `sampleTime` court en continu à travers les fichiers.

**iOS — crossfade (1…12 s).** Deux `Deck` (player + `fadeMixer`), sommés dans `sumMixer` (gain fixe 1.0) puis EQ. **Rampe equal-power** `cos²+sin²=1` (pas de creux -3 dB) ; progression dérivée de **l'horloge audio du deck entrant** (robuste au gel du RunLoop en arrière-plan), pas de l'horloge murale. Durée bornée à la moitié du titre sortant ET entrant (`effectiveFadeDuration`). `fadeMixer` convertit les sample-rates hétérogènes (pas de garde de fréquence, contrairement au gapless). Bascule atomique d'identité (index/titre/durée) **au début** du fondu. `@AppStorage("crossfadeDuration")`, slider **0…12 s pas 1** ; libellé "Sans (gapless)" à 0.

**Android recommandé.**
- **Gapless** : **natif et gratuit** dans ExoPlayer pour FLAC/MP3/AAC encodés avec délai/padding — aucune planification manuelle à écrire. C'est un gros simplificateur vs iOS. Construire une `playlist` (`player.setMediaItems(...)`) ; ExoPlayer enchaîne sans blanc.
- **Crossfade** : ⚠️ **point le plus difficile à reproduire** (voir section difficulté). ExoPlayer n'a **pas** de crossfade intégré ni de mixage multi-piste. Reproduction fidèle = **deux instances `ExoPlayer`** (deckA/deckB), chacune routée vers son propre gain (`player.volume` ou `AudioProcessor`), pilotées par une rampe equal-power `cos/sin` sur un `Choreographer`/coroutine cadencée. Dériver la progression de `deckB.currentPosition` (horloge audio) pour rester robuste en arrière-plan, exactement comme iOS. La sommation se fait alors au niveau du `AudioTrack`/mixer système (deux players → deux AudioTracks). Le calage atomique d'identité et les bornes demi-titre sont du code applicatif portable 1:1.

---

### 5. Spectre temps réel (FFT vDSP — `AudioSpectrumAnalyzer.swift`)

**iOS.** Tap sur `mainMixerNode` (`installTap`, bufferSize = `fftSize`). **FFT Accelerate/vDSP** : `fftSize = 1024`, **fenêtre de Hann** (`vDSP_hann_window`), `vDSP_fft_zrip` radix-2, magnitudes `vDSP_zvmags` → amplitude `vvsqrtf`. Regroupement en **48 bandes log** (`bandCount`), normalisation dB perceptuelle : `db = 20·log10(avg+1e-7)` puis `(db+20)/50` borné 0…1 (≈ -20…+30 dB). Forme d'onde = sous-échantillonnage brut sur **128 points**. Lissage UI dans `applySpectrum` : **attaque rapide / chute lente** (`target > cur ? target : cur*0.80 + target*0.20`). `NSLock` pour la sécurité thread audio vs deinit.

**Android recommandé.** Deux voies :
- **Simple** : `android.media.audiofx.Visualizer` attaché à l'`audioSessionId` — fournit `getFft()` (bandes prêtes) et `getWaveform()`. Rapide à câbler MAIS résolution/qualité moindres, captures limitées, nécessite permission `RECORD_AUDIO`, et bypassée par certains chemins de rendu. Donne un rendu "correct" mais pas pixel-identique aux 48 bandes log.
- **Fidèle** : `AudioProcessor` (ou `TeeAudioProcessor` / `AudioBufferSink`) qui intercepte le PCM, puis **FFT custom** en Kotlin/C — utiliser `JTransform`, `KissFFT` (NDK) ou un `noise`/Oboe FFT, avec **la même fenêtre Hann, fftSize 1024, 48 bandes log, même normalisation dB et même lissage attaque/chute**. C'est la seule façon d'obtenir un `SpectrumRingView`/`GrooveRingView` identique. Recommandé : `TeeAudioProcessor` (existe dans Media3) qui te livre les buffers sans modifier la lecture.

---

### 6. Minuterie de veille avec fondu

**iOS.** `setSleepTimer(minutes:)` ou `setSleepTimerEndOfTrack()` (temps restant). `Timer` non répétitif → `fadeOutAndPause` : **fondu ~4 s** sur `engine.mainMixerNode.outputVolume` (40 pas × 0,1 s), puis `togglePlayPause()` (pause propre gapless/crossfade), puis **restauration du volume utilisateur** (pour ne pas redémarrer muet). `sleepTimerEndDate` exposé pour le décompte UI.

**Android recommandé.** Portable 1:1. `Handler.postDelayed` / coroutine `delay`, ou `CountDownTimer`. Le fondu : rampe sur `player.volume` (40 pas × 100 ms), puis `player.pause()`, puis restaurer le volume mémorisé. Pour la fin de piste : `player.duration - player.currentPosition`. Exposer un `endDate`/`StateFlow<Long>` pour le décompte.

---

### 7. Volume

**iOS.** `volume: Float` (0…1) → `engine.mainMixerNode.outputVolume` (didSet borné). Distinct du gain RG (par-source) et de l'EQ.

**Android.** `exoPlayer.volume` (0…1, gain logiciel app, n'affecte pas le volume système). Garder séparé du gain RG (processor) comme iOS.

---

### 8. Lecture en fond + commandes distantes (MPRemoteCommandCenter / Now Playing)

**iOS.** `configureAudioSession` : `AVAudioSession` catégorie `.playback`, observer `routeChangeNotification` → `refreshAudioOutput`. `setupRemoteCommands` (`MPRemoteCommandCenter`) : play, pause, togglePlayPause, next, previous, `changePlaybackPosition` (seek). `updateNowPlayingInfo` → `MPNowPlayingInfoCenter` (titre, artiste, album, durée, position élapsée, rate, **artwork** `MPMediaItemArtwork`). Plus un **widget écran d'accueil** via `NowPlayingWidgetBridge` (App Group `group.kohlnet.Sillon`, fichier `np-cover.dat`, `WidgetCenter.reloadAllTimelines`).

**Android recommandé.**
- **Fond + contrôles système** : `androidx.media3.session.MediaSessionService` (foreground service) + `MediaSession` lié à l'ExoPlayer. Media3 publie **automatiquement** la notification média (style `MediaStyle`) et l'écran verrouillé — pas besoin de mapper chaque commande à la main (play/pause/next/prev/seek câblés via les `Player.Commands`). C'est plus simple que iOS.
- **Métadonnées Now Playing** : `MediaItem.MediaMetadata` (title, artist, albumTitle, `artworkUri`/`artworkData`, durée). La position/rate sont dérivés du player automatiquement.
- **Audio focus / route** : géré par `setAudioAttributes(..., handleAudioFocus = true)` ; route/device + **codec Bluetooth** via `AudioManager` + `BluetoothCodecConfig` (`getCodecType()` → SBC/AAC/aptX/LDAC). ⭐ Note importante : `AudioOutput.codec` est **`nil` sur iOS par design** et le commentaire du fichier `AudioOutput.swift` indique explicitement que ce champ « sera renseigné par la future version Android via `BluetoothCodecConfig` » — c'est un endroit où Android sera **meilleur** que l'iOS.
- **Widget** : `Glance` (Jetpack) ou `AppWidgetProvider` ; partage d'état via `DataStore`/fichier au lieu de l'App Group.

---

### Récapitulatif : ce qui sera LE PLUS DIFFICILE à reproduire fidèlement

1. **Crossfade deux decks (le plus dur).** Aucun support natif Media3. Nécessite deux `ExoPlayer` synchronisés, rampe equal-power pilotée par l'horloge audio du deck entrant, bascule atomique d'identité, bornes demi-titre. Risque de désynchro/glitch au mixage de deux `AudioTrack`. C'est le composant le plus exposé aux régressions.
2. **Égaliseur paramétrique 6–12 bandes 32 Hz–16 kHz custom.** `Equalizer` système ne suffit pas (bandes/fréquences imposées). Il faut écrire un DSP biquad par bande dans un `AudioProcessor` pour matcher `EQBands` + les 3 modes (normal/paramétrique/graphique).
3. **Spectre FFT 48 bandes log pixel-identique.** `Visualizer` natif ne donnera pas la même résolution/normalisation. Pour égaler `SpectrumRingView`/`GrooveRingView`, refaire FFT (Hann, 1024, 48 bandes log, dB `(db+20)/50`, lissage attaque/chute) via `TeeAudioProcessor`.
4. **Application du gain ReplayGain par-source pendant le crossfade.** Sur iOS chaque deck porte son `player.volume`. Sur Android, avec deux ExoPlayers c'est faisable, mais il faut un `AudioProcessor` de gain par deck (pas le `player.volume` global qui se confondrait avec le volume utilisateur).

Ce qui sera **plus simple** côté Android : gapless (natif ExoPlayer), streaming/cache (`CacheDataSource` — supprime le « download complet d'abord » de la Phase 1 iOS), notification/contrôles système et lecture en fond (`MediaSessionService` automatique), et le codec Bluetooth (exposé par `BluetoothCodecConfig`, indisponible sur iOS).

Fichiers iOS de référence : `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Player/PlayerController.swift`, `AudioSpectrumAnalyzer.swift`, `ReplayGain.swift`, `ReplayGainMode.swift`, `EQBands.swift`, `EQSettingsStore.swift`, `AudioOutput.swift`, `NowPlayingWidgetBridge.swift` ; modèle `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Models/EQSettings.swift` ; réglages `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Views/Settings/PlaybackSettingsView.swift`.

---

# Écrans & composants UI

J'ai maintenant une vue complète de l'application. Je rédige le guide de portage Android.

# Portage Android (Kotlin + Jetpack Compose) de « Sillon »

> Cette section donne, écran par écran et composant par composant, les valeurs exactes du source iOS/SwiftUI et leur équivalent Compose recommandé pour une réplique quasi identique. Tous les chemins sont absolus sous `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/`.

## 0. Fondations — Design System

Source : `DesignSystem/Theme.swift`. À porter dans un package `ui/theme/` (`Color.kt`, `Type.kt`, `Spacing.kt`, `SillonTheme.kt`).

### Palette (couleurs adaptatives clair/sombre — défaut = sombre)

| Token iOS (`Palette.*`) | Clair `0xRRGGBB` | Sombre `0xRRGGBB` | Usage | Équivalent Compose |
|---|---|---|---|---|
| `fondNoir` | `F6F4EF` | `0B0D0F` | Fond principal | `MaterialTheme.colorScheme.background` |
| `surfaceElevee` | `FFFFFF` | `15181B` | Cartes, feuilles, lignes survolées | `surface` / `surfaceVariant` |
| `accentCuivre` | `B06D2C` | `D98E4A` | Accent : favori, lecture en cours, sliders | `primary` |
| `signalTeal` | `2E7D75` | `4FA8A0` | Données techniques (bitrate, codec, sync, EQ actif) | couleur custom `signalTeal` hors `colorScheme` |
| `texteIvoire` | `1C1A17` | `F3F1EC` | Texte principal | `onBackground` / `onSurface` |
| `texteSourdine` | `6E6A64` | `9A9590` | Texte secondaire, métadonnées | `onSurfaceVariant` |

- Hex helper iOS `Color(hex:)` → en Compose `Color(0xFF000000 or hex)`.
- Dual clair/sombre `Color(light:dark:)` → deux `ColorScheme` (`lightColorScheme()` / `darkColorScheme()`) + un `data class SillonColors` pour les tokens hors Material (`signalTeal`) exposé via `CompositionLocal` (`staticCompositionLocalOf`). Le défaut de l'app est **sombre** (`appearanceMode = .sombre`).
- `placeholderGradient(seed:)` : hash **déterministe djb2** (`reduce(5381) { $0*33 + scalar }`), `hue = hash % 360 / 360`, deux couleurs HSB : base `sat 0.28 / bright 0.34`, dark `sat 0.35 / bright 0.18`, en `LinearGradient` topLeading→bottomTrailing. À répliquer exactement (même algorithme djb2, pas `hashCode()` Kotlin qui n'est pas garanti stable inter-process de la même façon — réimplémenter le djb2). Compose : `Brush.linearGradient(listOf(base, dark))` + conversion HSV→RGB via `Color.hsv(h*360f, s, v)`.

### Typographie (`Typo`)

| Token | Police iOS | Équivalent Compose |
|---|---|---|
| `display` | `.title` serif | `FontFamily.Serif`, ~28sp, normal |
| `displaySmall` | `.title3` serif, medium | Serif ~20sp, `FontWeight.Medium` |
| `paroleActive` | **`.title2` serif, semibold** (ligne de paroles en cours, agrandie) | Serif ~22sp, `FontWeight.SemiBold` |
| `corps` | `.body` default (SF Pro) | `FontFamily.Default`/Roboto, 17sp |
| `technique` | `.caption` **monospace** | `FontFamily.Monospace`, 12-13sp |

Le contraste fondateur est : **serif chaud pour la musique** / **monospace + teal pour les données techniques** (bitrate, codec, dB, horodatages). Conserver impérativement `FontFamily.Monospace` + couleur `signalTeal` partout où le source applique `Typo.technique` / `.techniqueData()`.

### Espacement (`Spacing`) → simples `Dp`

`xs=4 · s=8 · m=12 · l=16 · xl=24 · xxl=32`, `cardCorner=10`. Créer un `object Spacing { val xs = 4.dp; … ; val cardCorner = 10.dp }`. Les coins iOS sont `RoundedRectangle(cornerRadius:, style: .continuous)` → `RoundedCornerShape(10.dp)` (Compose n'a pas de squircle « continuous » natif ; `RoundedCornerShape` est l'approximation acceptable).

### Apparence (`AppearanceMode`)

`systeme / clair / sombre` → réglage persistant (DataStore). `systeme` ⇒ `isSystemInDarkTheme()`. Icônes : `circle.lefthalf.filled / sun.max / moon`.

---

## 1. Navigation racine

Source : `App/RootTabView.swift`, `App/SidebarRootView.swift`.

- **iPhone & téléphone Android** : `TabView` à 5 onglets en bas → `Scaffold(bottomBar = { NavigationBar { … } })` avec `NavHost`.
- **iPad paysage / macOS** : `NavigationSplitView` (barre latérale 172/196/240 pt) → sur tablette Android, `NavigationRail` ou `PermanentNavigationDrawer` selon largeur (`WindowSizeClass`, `Expanded` → rail/drawer ; `Compact/Medium` → bottom bar).
- 5 destinations (ordre + icônes SF → Material) :

| Onglet | Icône SF | Material Icons |
|---|---|---|
| Accueil | `house.fill` | `Icons.Filled.Home` |
| Bibliothèque | `music.note.list` | `Icons.AutoMirrored.Filled.QueueMusic` |
| Favoris | `heart.fill` | `Icons.Filled.Favorite` |
| Recherche | `magnifyingglass` | `Icons.Filled.Search` |
| Réglages | `gearshape.fill` | `Icons.Filled.Settings` |

- Le mini-lecteur (`NowPlayingBar`) n'est ancré **que si un morceau joue** (`tabViewBottomAccessory` iOS 26 / `safeAreaInset` macOS) → en Compose, slot custom au-dessus de la `NavigationBar` dans le `Scaffold` (`bottomBar` = `Column { NowPlayingBar(); NavigationBar() }`), conditionné par `currentTrack != null`.
- Navigation value-based SwiftUI (`navigationDestination(for:)`) → routes typées Navigation-Compose (`navController.navigate("album/{id}")`), avec un seul graph qui résout `Album`/`Artist`/`Playlist`.
- Environnement `hasMultipleServers` (≥2 serveurs **actifs**) pilote l'affichage des pastilles de source → exposer via `CompositionLocal` ou champ du ViewModel observé.

---

## 2. Accueil (`Views/Home/HomeView.swift`)

Pile verticale défilante de **carrousels horizontaux**, sections vides masquées.

**Structure** : `ScrollView` + `VStack(spacing: xxl=32)` → **`LazyColumn`** (`verticalArrangement = spacedBy(32.dp)`, `contentPadding` vertical 16.dp).

1. **Accès rapides** (`quickActions`) : `HStack(spacing: m=12)` de 3 cartes égales → `Row` de 3 `QuickAction` en `Modifier.weight(1f)`. Chaque carte : `VStack` icône (`.title3`, teal) + libellé (`.caption` medium, ivoire), hauteur **64**, fond `surfaceElevee`, coins `cardCorner=10`. → `Card`/`Surface` hauteur 64.dp, `Column(horizontalAlignment = CenterHorizontally)`. Items : « Albums » (`square.stack.fill`), « Artistes » (`music.mic`), « Mixer les favoris » (`shuffle`, désactivé si aucun favori).
2. **Carrousels d'albums** (`HomeSection` + `albumCarousel`) : titre `displaySmall` ivoire (padding horizontal 16) puis `ScrollView(.horizontal)` `HStack(spacing: l=16, alignment: .top)` → **`LazyRow`** (`contentPadding = horizontal 16.dp`, `spacedBy(16.dp)`). Carte d'album taille **160** sur l'Accueil.
   - Sections, dans l'ordre, masquées si vides : « Albums récents » (limit 30), « Albums préférés » (30), « Redécouvrir des albums » (15, overscroll = re-tirage), « Continuer l'écoute » (5), « Pistes préférées » (`TrackCard` size 150, 20 max), « Albums aléatoires » (15, overscroll = re-tirage), « Playlists » (`PlaylistChip`, 12 max).
3. **Geste « overscroll » sur Redécouvrir/Aléatoires** : tirer le carrousel au-delà d'un bord (seuil **>70**, réarmement **<20**) re-mélange + retour haptique léger (`shuffleToken`). → Compose : observer `LazyListState` (premier/dernier item visible + `NestedScrollConnection` pour mesurer l'overscroll), déclencher `regenerate*()` + `HapticFeedback`. Animation `easeInOut 0.3s`.
4. **PlaylistChip** : carré **130×130** `surfaceElevee` coins 10, icône `music.note.list` (size 30 light) cuivre, + nom `.subheadline` ivoire (1 ligne).
5. **État vide** (`LibraryEmptyState`) : titre « Votre disquaire est vide », icône `opticaldisc`.

**Sélections figées** : « Redécouvrir » et « Albums aléatoires » sont tirées **une seule fois** au chargement (`generateDiscoveryIfNeeded`, pas de re-mélange à chaque recomposition). → en Compose, stocker dans le `ViewModel` (`StateFlow`), pas recalculer dans le `@Composable`. « Redécouvrir » privilégie les albums `lastPlayedDate == nil` si ≥15, sinon tout le catalogue.

---

## 3. Bibliothèque

Source : `Views/Library/LibraryRootView.swift` (+ sous-vues).

- **Sélecteur segmenté** 5 sections : `Récents · Artistes · Albums · Titres · Playlists` (`Picker(.segmented)`, défaut **Albums**) → `SingleChoiceSegmentedButtonRow` (Material3) ou `TabRow`. Padding 16, suivi d'un `Divider`.
- **Barre de recherche** `.searchable` (prompt « Artistes, albums, titres ») qui, dès qu'on tape, remplace tout le contenu par `SearchResultsView` → `SearchBar` Material3 ou `TextField` en `topBar`.
- **Toolbar** : menu de tri (visible en section Albums) + bouton « Parcourir » (`rectangle.3.group`).
- Titre `inline`.

### Grille d'albums (`AlbumsGridView.swift`)
- `LazyVGrid(columns: .adaptive(minimum: 150), spacing: l=16)`, espacement vertical `xl=24`, padding 16 → **`LazyVerticalGrid(columns = GridCells.Adaptive(minSize = 150.dp))`**, `verticalArrangement`/`horizontalArrangement = spacedBy(...)`.
- **Tri** (`AlbumSortOrder`) : `titre · artiste · annee · recent` ; icônes `textformat / music.mic / calendar / clock`. → menu déroulant (`DropdownMenu`) avec `RadioButton`.

### Détail d'album (`AlbumDetailView`)
- `List` plain = en-tête + section pistes → **`LazyColumn`** avec un item header + items pistes.
- **Header** : `HStack(top, spacing 16)` → pochette **120×120** (`CoverArtView` avec `showsSource: true`), à droite `VStack` : titre `displaySmall` ivoire, artiste `.subheadline` secondaire, **ligne métadonnées** `année · N titres · durée` en `Typo.technique` teal, **ligne encodage** (`FLAC` ou `ALAC · FLAC · MP3`) en technique teal.
- **Lignes** : `TrackRowView(showsTrackNumber: true, showsMenu: true)`, tap = lecture à l'index, menu contextuel.
- **Toolbar** : bouton favori (cœur, `prominent`) + bouton « Télécharger l'album » (`arrow.down.circle`, masqué pour serveur `.local` ou album vide).

### Artistes (`ArtistsListView.swift`)
- `List` plain → **`LazyColumn`**. `ArtistRow` : pochette 44×44 (symbole `music.mic`), nom `.headline`, sous-titre « N albums », cœur cuivre si favori.
- **Détail artiste** (`ArtistDetailView`) : grille d'albums `adaptive(150)`, `AlbumCard` taille défaut 150, toolbar bouton favori.

### Titres (`TracksListView.swift`)
- `List` plain de `TrackRowView(showsTrackNumber: false, showsArtwork: true)` triés par titre → **`LazyColumn`** (penser à `key = track.id` pour ~16k items). Tap = lecture file à l'index.

### Récents (`RecentAdditionsView.swift`) — non lu en détail mais réutilise grille/cartes.

### Parcourir (`BrowseViews.swift`)
- `BrowseRootView` : `List` 2 entrées « Par genre » (`guitars`) / « Par décennie » (`calendar`).
- `GenresListView` / `DecadesListView` : `List` simple ; `GenreTracksView` (liste pistes + bouton « Mélanger » toolbar) ; `DecadeAlbumsView` (grille `adaptive(150)`). Décennie affichée `"\(year)s"`.

---

## 4. Recherche

Source : `Views/Search/SearchView.swift`, `SearchResultsView.swift`.

- **Onglet dédié** : `NavigationStack` + `.searchable` (prompt « Artistes, albums, titres »). Sans saisie → `ContentUnavailableView("Rechercher", magnifyingglass, …)`. → `Scaffold` + `SearchBar`, état vide = `Column` centrée icône+texte.
- **Résultats** (`SearchResultsView`) : `List` plain à 3 sections `Section("Artistes"/"Albums"/"Titres")` → **`LazyColumn`** avec en-têtes de section (`stickyHeader` ou item titre).
  - `artistRow` : pochette 40×40 (`music.mic`) + nom `.headline`.
  - `albumRow` : pochette 40×40 + titre `.headline` + artiste `.caption`.
  - titres : `TrackRowView(showsArtwork: true)`.
- Recherche **locale, insensible casse/accents** (`localizedStandardContains`) → en Room, `LIKE` + `COLLATE NOCASE` (et normalisation accents) ; limites : 20 artistes / 20 albums / 50 titres (× nb serveurs actifs avant dédup). Relancée quand requête, ensemble serveurs actifs, ou `mergeDuplicates` change.

---

## 5. Favoris (`Views/Favorites/FavoritesView.swift`)

- Sélecteur segmenté 2 sections **Albums / Titres** (défaut Albums) → `SingleChoiceSegmentedButtonRow`.
- État vide global : `ContentUnavailableView("Aucun favori", heart, …)`.
- **Albums** : grille `adaptive(150)`, `AlbumCard`.
- **Titres** : bouton **« Mixer les favoris »** (`shuffle`, `borderedProminent` teinté **cuivre**) centré, puis `LazyVStack` de `TrackRowView(showsArtwork: true)` (padding h 16, v `xs=4`), tap = lecture file. → `Button` Material3 `containerColor = accentCuivre`, puis `LazyColumn`.
- Tri par `favoriteDate` desc.

---

## 6. Réglages

Source : `Views/Settings/SettingsRootView.swift`.

- `List` (Form) avec :
  1. **Apparence** : `Picker(.menu)` (`circle.lefthalf.filled`) — Système/Clair/Sombre.
  2. **Langue** : `Picker(.navigationLink)` (`globe`) ~11 entrées → sous-page liste sur Android (`navigate` vers une liste de `RadioButton`). Applique la redirection de bundle **avant** de reconstruire la racine.
  3. **Serveurs** (`server.rack`) → `ServerListView`.
  4. **Téléchargements** (`arrow.down.circle`) → `DownloadsView`.
  5. **Égaliseur** (`slider.vertical.3`) → `EQView`.
  6. **Lecture** (`play.circle`) → `PlaybackSettingsView`.
- → `LazyColumn` de `ListItem` (leading icon, trailing valeur/chevron). Persistance `@AppStorage` → **DataStore Preferences**. Clés à conserver : `appearanceMode`, `mergeServerDuplicates`, `crossfadeDuration`, `replayGainMode`, `replayGainClipProtection`, `replayGainPreampDB`, `spectrumStyle`, langue.

### Langue
- Source localisation : `Localization/` + `LanguageManager`. iOS redirige le `Bundle`. Android : `AppCompatDelegate.setApplicationLocales(LocaleListCompat)` (per-app language, API 33+ / AppCompat) + ressources `res/values-xx/strings.xml`. `LanguageManager.string(...)` → `stringResource(...)`. Langues citées pour la traduction de paroles : `de, fr, it, es, en`.

### Serveurs (`Views/Servers/`)
- **`ServerListView`** : `List` ; vide → `ContentUnavailableView("Aucun serveur", server.rack, …)`. Sinon section de `ServerRowView` avec **swipe-to-delete** (`onDelete`) et **réordonnancement** (`onMove`, met à jour `sortOrder`). → `LazyColumn` + `SwipeToDismissBox` + lib reorderable (ex. `sh.calvin.reorderable`). Footer (≥2 serveurs) : « Le serveur du haut est prioritaire… ». Section toggle **« Fusionner les doublons »** (`mergeDuplicates`, teint teal).
- **`ServerRowView`** : icône type 30×30 (logos vectoriels `JellyfinMark`/`NavidromeMark`, ou symbole cuivré pour local) ; opacité **0.4** si inactif ; nom `.headline` + sous-titre monospace (« Dernière synchro : … » / « Jamais synchronisé »). **Toggle actif/inactif** (teal). Bouton trailing selon état sync : `idle`→« Synchroniser » (bordered), `syncing`→`ProgressView` linéaire (largeur 90) + libellé de phase monospace, `failed`→« Réessayer » (rouge). → `LinearProgressIndicator`, `Switch`, `OutlinedButton`.
- **`AddServerView`** : `Form` modal (`.sheet`) → `ModalBottomSheet` ou écran plein. Picker type (`Jellyfin/Subsonic/Local`, inline) ; champs conditionnels :
  - Jellyfin : nom, URL (`https://…`, no-autocap, keyboard URL), username, password (`SecureField`→`PasswordVisualTransformation`).
  - Subsonic : idem + **mode auth segmenté** (password / token+salt), champs token & salt.
  - Local : nom + bouton « Choisir un dossier… » (`fileImporter` `.folder`) → **SAF** Android (`ACTION_OPEN_DOCUMENT_TREE` / `OpenDocumentTree`), permission persistée.
  - Bouton « Tester la connexion » (spinner) ; avertissement orange si URL `http` (`lock.open.trianglebadge.exclamationmark`) ; résultat ✓ vert / ✗ rouge. **« Enregistrer » désactivé tant que le test n'a pas réussi.**

### Téléchargements (`Views/Downloads/DownloadsView.swift`)
- `List` de `DownloadRow` triés `queuedAt` desc ; vide → `ContentUnavailableView("Aucun téléchargement", arrow.down.circle, …)`. → `LazyColumn`.
- **`DownloadRow`** : pochette 44×44 avec **badge d'état** en coin bas-droite (cercle teinté, icône blanche, contour blanc) ; teintes : terminé=teal, échec=rouge, autres=cuivre. Titre `corps`, et si `downloading` → **`ProgressView(.linear)`** + « N % » monospace, sinon sous-titre monospace (« Téléchargé »/« En attente »/erreur rouge). Logo source 18×18 si ≥2 serveurs **configurés**. Action trailing : annuler (`xmark.circle.fill`) / réessayer (bordered) / supprimer (`trash`).

### Égaliseur (`Views/Player/EQView.swift`) — écran riche
- `NavigationStack`, fond `fondNoir`, toolbar : « sauvegarder en preset » (`tray.and.arrow.down.fill`, teal, désactivé si 9 presets) + « OK ».
- **Toggle** « Égaliseur activé » (teal). **Picker segmenté** Mode : `Normal / Paramétrique / Graphique` (`EQMode`). **Stepper** « Bandes : N » bornes **6…12**.
- **Mode Normal** : `HStack` de **sliders verticaux** (`Slider` `.rotationEffect(-90°)`, frame 30×180, plage **-12…+12 dB**), au-dessus la valeur `%+.0f` monospace teal, dessous le label de fréquence. → Compose : `Slider` dans un `Box` avec `Modifier.graphicsLayer { rotationZ = -90f }` ou un slider vertical custom. Hauteur zone 240, espacement adaptatif `max(2, 30 - count*2)`.
- **Mode Paramétrique** : `ScrollView` de cartes par bande (`surfaceElevee`, coins 10), chacune : en-tête « Bande N » + « f Hz · ±g dB · b oct » (monospace teal), 3 sliders **Gain / Fréq (log 20 Hz–20 kHz) / Largeur (0.1–3.0)**.
- **Mode Graphique** : `EQCurveView` (courbe à poignées drag fréquence↔ / gain↕, tap = sélection) → `Canvas` + `detectDragGestures`/`detectTapGestures` (`pointerInput`). Contrôle largeur de la bande sélectionnée.
- **Presets** : panneau superposé (`ZStack`, fond opaque `fondNoir`) ouvert par bouton-capsule (`rectangle.stack.fill`, cuivre si actif). Lignes preset : `TextField(.roundedBorder)` nom + 3 boutons (enregistrer cuivre / appliquer teal / supprimer rouge) ; ligne d'ajout `+`. Max **9 presets par mode**. → `Card` overlay + `OutlinedTextField`.
- Les changements **s'appliquent en direct** (`commit` → `player.refreshEQ()`) ; persistance singleton `EQSettings` (Room) + presets `EQPreset`.

### Lecture (`Views/Settings/PlaybackSettingsView.swift`)
- `Form` → `LazyColumn` de sections, fond `fondNoir` (`scrollContentBackground(.hidden)`).
- **Crossfade** : `Slider` `0…12 s step 1` (cuivre), libellé « Sans (gapless) » à 0, sinon « N s » (technique teal).
- **ReplayGain** : `Picker(.menu)` Normalisation (`ReplayGainMode`, teint cuivre) ; toggle « Protection anti-saturation » (teal, désactivé si off) ; slider « Pré-amplification » `-6…+6 dB step 1`, libellé `%+.0f dB` technique, opacité 0.4 si off.
- Tout changement appelle un `refresh*()` du player → ViewModel observe DataStore et notifie le service de lecture.

---

## 7. Lecteur plein écran (`Views/Player/PlayerView.swift`)

Le plus complexe. Présenté en `fullScreenCover` (iPhone) / inline zone de détail (macOS/iPad paysage). → écran Compose plein, avec `onClose` pour la version inline tablette.

**Disposition adaptative** via `GeometryReader` (`width > height` = paysage) → en Compose `BoxWithConstraints` (`maxWidth > maxHeight`).

- **Portrait** : `VStack(spacing: xl=24)` : `topBar` · `Spacer` · **visuel central** (pochette+spectre, `maxSide 344`, padding bas `xxl=32` sauf paroles) · `titles` · `progressSection` · `transport` · `volumeSection` · `bottomRow` · `Spacer`. → `Column`.
- **Paysage / tablette** : `topBar` puis `HStack(spacing: xl)` **deux colonnes** : visuel à gauche (`coverMax = min(w*0.45, h*0.82, 640)`), à droite `VStack` centrée (largeur `min(w*0.46, 480)`) titres + transport + contrôles. → `Row` de deux `Column`/`Box`, largeurs calculées depuis `maxWidth/maxHeight`.
- Habillage commun : padding h `xl=24` / v `l=16`, fond `fondNoir`, animation `easeInOut 0.25` sur bascule paroles.

**topBar** (`HStack`) : bouton fermer `chevron.down` ; menu **Visualisation** (`Picker` inline des `SpectrumStyle`) ; **minuterie de sommeil** (`moon.zzz` → `moon.zzz.fill` cuivre si active ; options 15/30/45/60 min, « Fin du morceau », « Désactiver ») ; bouton **EQ** `slider.vertical.3` teal. → `Row` + `IconButton` + `DropdownMenu`.

**Visuel central** (`mainVisual`) : pochette+spectre **OU** `LyricsView` (toggle, transport reste accessible). `artwork` selon `spectrumStyle` :
- `.off` → pochette **ronde** agrandie (`clipShape(Circle)`).
- `.offSquare` → carrée coins 16.
- spectre → `ZStack { SpectrumRingView ; cover ronde padding 28 }`.
→ Compose : `Box` ; pochette ronde = `Modifier.clip(CircleShape)` ; spectre = `Canvas` derrière.

**titles** : `VStack(spacing: xs=4)` centré : titre `Typo.display` ivoire (2 lignes), artiste `.headline` secondaire, album `.subheadline` secondaire (1 ligne).

**progressSection** : `Slider` (tint cuivre) lié à `scrubTime ?? currentTime`, plage `0…max(duration,0.1)` ; le seek se fait au **relâchement** → en Compose `Slider(onValueChange=…, onValueChangeFinished={ seek })`. Sous le slider : `HStack` temps écoulé / durée (technique secondaire) + badge qualité technique teal (`FLAC · 88,2 kHz`).

**transport** (`HStack spacing xl`) : `-10s` (`gobackward.10`), précédent (`backward.end.fill`), **play/pause** (`play.circle.fill`/`pause.circle.fill`, **size 64**), suivant (`forward.end.fill`), `+10s` (`goforward.10`). Spinner `isLoading` au centre. Icônes `.title2` ivoire. → `Row` d'`IconButton`, central plus grand.

**volumeSection** : `speaker.fill` + `Slider 0…1` (cuivre) + `speaker.wave.3.fill`. → `Slider` lié au volume du player.

**bottomRow** (`HStack` répartie par `Spacer`) : favori (`heart`/`heart.fill` cuivre si actif) · shuffle (cuivre si actif) · repeat (`repeatMode.systemImage`, cuivre si actif) · paroles (`quote.bubble`, cuivre si visible) · file (`list.bullet`) · **AirPlay** iOS (`RoutePickerView` `AVRoutePickerView`). → Android : remplacer AirPlay par **Cast/route audio** (`MediaRouteButton` AndroidX Mediarouter / `RoutePicker`), ou retirer si non pertinent.

**File d'attente** (`QueueView.swift`) : `.sheet` → `ModalBottomSheet`/écran. `List` réordonnable (`onMove` → lib reorderable) ; ligne : pochette 44 avec overlay « en lecture » (`speaker.wave.2.fill` sur voile noir 0.45) pour l'item courant ; titre cuivre si courant ; tap = `jump(to:)`. Vide → `ContentUnavailableView("File vide", list.bullet)`.

---

## 8. Vue Paroles (`Views/Player/LyricsView.swift`) — détail soigné

Intégrée **dans** le lecteur (remplace la pochette). Deux modes :

- **Synchronisées** (`SyncedLyricsView`) : `ScrollViewReader` + `LazyVStack(spacing: l=16)`. Ligne **active** = `Typo.paroleActive` (serif title2 semibold, **agrandie**) en **`accentCuivre`** ; lignes inactives = `Typo.corps` en `texteSourdine`, `scaleEffect 0.98`, `opacity 0.55`. **Auto-défilement** centrant la ligne courante (`scrollTo(i, anchor: .center)`, `easeInOut 0.35`). **Tap sur une ligne = seek** à son timecode. Animation `easeInOut 0.3` sur `isActive`.
  → Compose : `LazyColumn` + `rememberLazyListState`, `LaunchedEffect(activeIndex){ animateScrollToItem(...) }` (avec offset pour centrer), `Modifier.clickable { seek(line.timeSeconds) }`, `animateFloatAsState` pour scale/alpha. La ligne active doit ressortir (taille + couleur cuivre).
- **Non synchronisées** (`PlainLyricsView`) : `ScrollView` + `VStack(spacing: m=12)`, texte ivoire `corps` → `LazyColumn`/`Column` scrollable.
- **Traduction** (façon Apple Music) : bouton « Traduire »/« Original » en haut-droite (capsule `ultraThinMaterial`, devient teal si actif). Sous chaque ligne, **traduction en `signalTeal` (vert/teal)** quand activée. → **Différence majeure** : iOS utilise le framework **`Translation`** (sur l'appareil, gratuit). Android n'a pas d'équivalent système universel ; recommander **ML Kit Translation** (modèles téléchargeables on-device, gratuit) pour répliquer le on-device. Détection de langue = `NLLanguageRecognizer` → **ML Kit Language Identification**. Langues supportées identiques : `{de, fr, it, es, en}` ; bouton affiché seulement si source≠cible et toutes deux supportées.
- États : chargement → `ProgressView` (`CircularProgressIndicator`) ; pas de paroles → `ContentUnavailableView("Pas de paroles", quote.bubble)`.

---

## 9. Barre « Lecture en cours » (`Views/Player/NowPlayingBar.swift`)

`HStack(spacing: m=12)` : pochette **36×36**, `VStack` titre `.subheadline` ivoire + artiste `.caption` secondaire (1 ligne chacun), `Spacer`, bouton play/pause (`play.fill`/`pause.fill` `.title3`, zone 36×36). Tap global = ouvrir le lecteur plein écran. Le **fond est fourni par le conteneur** (la barre reste sobre).
→ Compose : `Row` dans une `Surface`, `Modifier.clickable { openPlayer() }`, hauteur ~56-64.dp, ancrée au-dessus de la `NavigationBar`.

---

## 10. Pochettes, cartes & placeholders

- **`CoverArtView.swift`** : carré (`aspectRatio 1`), `clip(RoundedCornerShape(cardCorner=10))`. `ZStack { placeholder ; AsyncImage }`. Image distante chargée cache-first (fichier local sync sinon download). → **Coil** `AsyncImage` avec `DiskCache`/`MemoryCache` ; le « cache-first » iOS (fichier local si déjà synchronisé) se mappe sur un `Fetcher`/`Interceptor` Coil ou un `model` qui pointe d'abord le fichier local.
  - **Placeholder** : si symbole défaut `music.note` → image **`SillonMark`** (le vinyle « Sillon », asset `Assets.xcassets/SillonMark.imageset`) en `scaledToFill`. Sinon dégradé déterministe djb2 + symbole (`size 28 light`, ivoire opacité 0.35).
  - **Pastille source** en bas-droite si `showsSource && hasMultipleServers` : `SourceCountBadge` si `sourceCount>1`, sinon `SourceBadge(type)`.
  - Re-résolution via `.task(id: "server|path")` car la relation serveur peut être nil au 1er rendu → en Compose, `key`/`LaunchedEffect(server?.id, path)`.
- **`AlbumCard.swift`** : `VStack(spacing: s=8)` : pochette (taille paramétrable, défaut 150, **160** sur Accueil), puis `VStack(spacing 2)` titre `.subheadline` ivoire (1 ligne) + artiste `.caption` secondaire (1 ligne), alignés sur la largeur de la pochette. → `Column` de largeur fixe = taille pochette.
- **`TrackRowView.swift`** : `HStack(spacing: m=12)` : leading (pochette 44 si `showsArtwork`, sinon n° de piste monospace largeur 28, sinon `music.note`), `VStack` titre `corps` + (artiste `.caption` OU badge technique teal monospace), `Spacer`, cœur cuivre si favori, `DownloadButton`, durée technique secondaire `monospacedDigit`, bouton menu `⋮` optionnel. → `Row` + `ListItem` custom.
- **`SourceBadge.swift`** :
  - `SourceBadge` : logo serveur 20×20 sur **cercle blanc fixe** + contour `black 0.12` + ombre, padding interne par marque (subsonic 1.5 / jellyfin 3 / local 4). Local = symbole `internaldrive`/dossier gris foncé. → `Box(Modifier.size(20.dp).clip(CircleShape).background(Color.White))` + `shadow`.
  - `SourceCountBadge` : `HStack` `square.stack.fill` (8) + compteur (10 rounded bold), blanc sur capsule `black 0.6`, contour blanc 0.3. → `Row` dans `Surface(shape = CircleShape)`.

### Logos serveurs vectoriels (`Views/Shared/ServerMarks.swift`)
Dessinés en **vectoriel** (pas d'asset), à reproduire en Compose `Canvas`/`Path` ou `VectorPainter` :
- **`JellyfinMark`** : 3 triangles arrondis concentriques (extérieur scale 1 trim 12 / trou scale 0.6 trim 7.2 / plein scale 0.34 trim 4.1) en espace 48×48, remplissage **even-odd**, dégradé `#AA5CC3 → #00A4DC` topLeading→bottomTrailing. Coins arrondis via quad-curves au sommet. → `Path` Compose avec `PathFillType.EvenOdd` + `Brush.linearGradient`.
- **`NavidromeMark`** : disque vinyle bleu `RGB(0.12,0.55,1.0)`, sillons (2 arcs haut-gauche 180→270° + 2 arcs bas-droite 0→90°, facteurs 0.74/0.56), étiquette blanche centrale (0.34), trou noir (0.07), contour noir (0.085). → `Canvas` `drawArc`/`drawCircle`.

---

## 11. Visualiseur de spectre (`Views/Player/SpectrumRingView.swift`)

Couronne autour de la pochette, rendue en **`Canvas`** SwiftUI → **`Canvas`** Compose (`drawIntoCanvas`/`drawPath`/`drawLine`). 5 styles + 2 « off » (`SpectrumStyle`) :
- `circularBars`, `bars`, `waveform`, `cascade`, `oscilloscope`, `off` (vignette ronde), `offSquare` (carrée).
- Entrées : `levels: [Float]` 0…1 (graves→aigus, **miroités** gauche/droite), `waveform: [Float]` -1…1. Couleurs : barres cuivre, pics et oscilloscope/cascade teal. Géométrie : `maxBar = min(w,h)*0.07`, base = rayon - maxBar - 1.
- L'historique (cascade) accumule 18 frames → en Compose, garder un `mutableStateListOf`/buffer dans le ViewModel ou un `remember`. Le spectre suit les `StateFlow` du player (magnitudes FFT) → à 30-60 fps via `withFrameNanos`. Icônes des styles : `circle.dotted / chart.bar.fill / wave.3.right / square.stack.3d.up.fill / waveform.path.ecg / circle / square`.

> Côté Android, alimenter `levels` via `Visualizer` (FFT) sur l'`audioSessionId` d'ExoPlayer/Media3, ou un tap PCM custom. C'est la pièce technique la plus sensible du portage.

---

## 12. Widget (`SillonWidget/SillonWidget.swift`) → Glance

Widget « Lecture en cours », familles `systemMedium` & `systemLarge` → **Jetpack Glance** `GlanceAppWidget` (tailles `SizeMode.Responsive` : medium ~`4×2`, large ~`4×4`).

- **Palette locale** dupliquée (mêmes hex que l'app) + couleurs spécifiques widget : `piste = light DCD7CC / dark 2C2F33`, `pochette = light C2A98A / dark 4A4036`. → `GlanceTheme`/`ColorProvider`.
- **Données via App Group** (`group.kohlnet.Sillon`) : `UserDefaults` partagés (clés `np.title/artist/album/elapsed/duration/anchor/quality/playing/favorite/has`) + fichier `np-cover.dat`. → Android : l'app écrit dans un **DataStore/`SharedPreferences`** ou via `GlanceAppWidget.update()` ; pochette = fichier dans `filesDir`/cache lu par Glance (`ImageProvider`). Le pont iOS est `Player/NowPlayingWidgetBridge.swift` (équivalent : `MediaSession` + worker qui pousse l'état au widget).
- **CoverSpectrum** : pochette ronde (réelle ou placeholder vinyle) + spectre **statique** dessiné au `Canvas` (44 barres, `sin*cos`). → Glance ne fait pas de Canvas riche : pré-rendre une image (bitmap du spectre) ou simplifier en image statique fournie par l'app.
- **MediumView** : `HStack` pochette 104 + colonne (titre serif 16, artiste 12, **barre de progression**, ligne temps/qualité/durée monospace, `TransportTrio` + cœur). → `Row`/`Column` Glance, `LinearProgressIndicator` Glance, boutons via `actionRunCallback`.
- **LargeView** : en-tête « Lecture en cours » (`opticaldisc`, cuivre) + « Sillon » serif ; pochette 96 + titre/artiste/album ; progression ; temps ; qualité teal ; rangée cœur / `TransportTrio` (cercle 46) / `list.bullet`.
- **Progression vivante** : iOS `ProgressView(timerInterval:)` (anim sans rechargement). Glance n'a pas d'équivalent natif → mettre à jour périodiquement (Worker) ou afficher une progression figée recalculée à chaque update. Conserver `virtualStart/virtualEnd` (anchor - elapsed) pour le calcul.
- **État vide** (`EmptyStateView`) : `opticaldisc` cuivre + « Rien en lecture » + « Sillon » serif.
- **Transport interactif** : iOS prévoit `AudioPlaybackIntent` → Glance : `actionRunCallback`/`actionStartActivity` vers le `MediaSession`/service.

---

## Récapitulatif mapping composants

| SwiftUI | Compose |
|---|---|
| `NavigationStack` / `navigationDestination(for:)` | `NavHost` + routes typées (Navigation-Compose) |
| `NavigationSplitView` (sidebar) | `NavigationRail` / `PermanentNavigationDrawer` (WindowSizeClass Expanded) |
| `TabView` + `Tab` | `Scaffold(bottomBar = NavigationBar)` |
| `ScrollView` + `VStack` | `LazyColumn` |
| `ScrollView(.horizontal)` + `HStack` | `LazyRow` |
| `LazyVGrid(adaptive: 150)` | `LazyVerticalGrid(GridCells.Adaptive(150.dp))` |
| `List` plain / `List(selection:)` | `LazyColumn` (+ `key`) |
| `Section("…")` | en-tête d'item / `stickyHeader` |
| `Picker(.segmented)` | `SingleChoiceSegmentedButtonRow` / `TabRow` |
| `Picker(.menu)` / `Menu` | `DropdownMenu` |
| `Picker(.navigationLink)` | sous-écran liste `RadioButton` |
| `Slider` (+ rotation -90°) | `Slider` (+ `graphicsLayer rotationZ`) ou slider vertical custom |
| `Toggle` | `Switch` |
| `Stepper` | `Row` `IconButton −/+` ou stepper custom |
| `.searchable` | `SearchBar` Material3 |
| `.sheet` / `.fullScreenCover` | `ModalBottomSheet` / écran plein |
| `ContentUnavailableView` | `Column` centrée (icône + titre + description) |
| `AsyncImage` | Coil `AsyncImage` (cache-first via fetcher) |
| `Canvas` (spectre, courbe EQ, logos) | `Canvas` / `Path` / `drawArc` |
| `ProgressView(.linear)` / `(value:)` | `LinearProgressIndicator` / `CircularProgressIndicator` |
| `.onMove` (réordonnancement) | lib reorderable (`sh.calvin.reorderable`) |
| `.onDelete` (swipe) | `SwipeToDismissBox` |
| `@AppStorage` | DataStore Preferences |
| `@Query` (SwiftData) | Room + Flow (`collectAsStateWithLifecycle`) |
| `sensoryFeedback` | `HapticFeedback` / `View.performHapticFeedback` |
| Framework `Translation` / `NLLanguageRecognizer` | **ML Kit** Translation + Language Identification (on-device) |
| `AVRoutePickerView` (AirPlay) | `MediaRouteButton` (Cast) ou retrait |
| WidgetKit (`StaticConfiguration`) | **Glance** `GlanceAppWidget` |
| Localisation par `Bundle`/`LanguageManager` | `res/values-xx` + `AppCompatDelegate.setApplicationLocales` |

**Points de vigilance pour la fidélité visuelle** : (1) le défaut **sombre** ; (2) la dualité **serif chaud / monospace teal** systématique ; (3) le placeholder vinyle déterministe (djb2, pas `hashCode`) ; (4) la ligne de paroles active **agrandie cuivre** + traduction **teal** ; (5) les coins `RoundedCornerShape(10.dp)` ; (6) les logos serveurs vectoriels reproduits au pixel ; (7) le spectre en couronne (Media3 `Visualizer`). Les fichiers source de référence sont tous sous `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Views/` et `/Users/thomaskohler/_DEV/Github/Sillon/SillonWidget/SillonWidget.swift`.

---

# Données, sync, téléchargements & i18n

J'ai tout le contexte nécessaire. Voici la documentation de portage.

## Portage Android — Persistance, Synchro, Téléchargements, Cache pochettes, Localisation, Traduction des paroles

### 1. Schéma de persistance : SwiftData (`@Model`) → Room

Modèles iOS déclarés dans `SillonSchema.models` (`Persistence/ModelContainerFactory.swift`) : `ServerAccount`, `Artist`, `Album`, `Track`, `Playlist`, `PlaylistItem`, `DownloadTask`, `EQSettings`, `EQPreset`.

Convention clé centrale à reproduire telle quelle : l'`id` de `Track`/`Album`/`Artist` est une **clé composite `"<serverID.uuidString>:<remoteID>"`** (`makeID(serverID:remoteID:)`), pour garantir l'unicité globale quand deux serveurs réutilisent le même `remoteID`. À conserver à l'identique côté Room (sinon les fichiers téléchargés, le cache pochettes et la déduplication ne correspondent plus).

Équivalent Room recommandé (`@Entity` + `@Dao`, base unique `SillonDatabase : RoomDatabase`) :

| SwiftData | Room | Notes de mapping |
|---|---|---|
| `@Attribute(.unique) var id: String` | `@PrimaryKey val id: String` | clé composite, même format |
| `@Attribute(.unique) var id: UUID` (`ServerAccount`, `Playlist`, `PlaylistItem`, `DownloadTask`) | `@PrimaryKey val id: String` (UUID en String) ou `@TypeConverter` UUID↔String | SQLite n'a pas de type UUID natif |
| `Int?`, `Double?`, `Date?`, `String?` | `Int?`, `Double?`, `Long?` (epoch millis via converter `Date`↔`Long`), `String?` | tous les optionnels ReplayGain/dates restent nullables |
| `enum ServerType: String` / `DownloadStatus: String` / `EQMode: String` | `enum class` + `@TypeConverter` (stocke `.name` / rawValue) | garder les rawValues `jellyfin`/`subsonic`/`local`, `notDownloaded`/`queued`/… identiques |
| `[Double]` (`gainsDB`, `frequencies`, `bandwidths`) | `List<Double>` via `@TypeConverter` JSON, ou table fille | SwiftData les sérialise de façon opaque ; en Room, JSON est le plus simple |

Relations (SwiftData `@Relationship` à sens unique + `deleteRule: .cascade`) → Room `@Relation` + clés étrangères :

- `ServerAccount 1—N Artist`, `Artist 1—N Album`, `Album 1—N Track` : ajouter `serverId: String?`, `artistId: String?`, `albumId: String?` comme colonnes FK. Cascade SwiftData → `@ForeignKey(onDelete = CASCADE)`. **Important** : `Track.server` et `Album.server` sont des références **directes** (en plus du chemin via l'artiste) — répliquer la colonne `serverId` directement sur `Track` et `Album` pour permettre filtrage/suppression rapides par serveur (utilisés dans `LibraryIndex` et le préchargement pochettes).
- `Playlist 1—N PlaylistItem` avec `position: Int` explicite (réordonnancement glisser-déposer) : table de liaison `PlaylistItem(id, position, trackId?, playlistId?)`. `orderedTracks` = `items.sortedBy { position }`. Reproduire en SQL : `ORDER BY position`.
- `EQSettings` est un **singleton** : `id` fixe `00000000-0000-0000-0000-000000000001`. En Room, garder cet id constant et un repository qui fait `getOrCreate`.
- `EQPreset` : 4 slots par mode (`EQMode.values()` × slots 1..4), semés une seule fois si table vide (`EQPresetStore.ensure`). Reproduire dans un `RoomDatabase.Callback.onCreate` ou au premier lancement.

Champs `ServerAccount` à porter intégralement : `isActive` (masquer sans supprimer), `sortOrder` (priorité dédup/affichage), `localFolderBookmark: Data?` (→ sur Android : **URI SAF persistée** `DocumentFile`/`takePersistableUriPermission`, stockée en `String?`), `negotiatedAPIVersion`, `syncCursor`, `lastFullSyncDate`/`lastDeltaSyncDate`, `createdAt`. `hasCompletedInitialSync = lastFullSyncDate != nil`.

Sécurité (rappel `ServerAccount`) : **aucun secret en base** (mot de passe / jeton / sel Subsonic). iOS = Keychain indexé par `id`. Android = **EncryptedSharedPreferences / Jetpack Security (Tink)** ou Keystore, indexé par `serverId`.

Migration : SwiftData fait des « migrations légères » (tout nouveau champ optionnel ou avec valeur par défaut). Room exige des `Migration` explicites — prévoir dès le départ `fallbackToDestructiveMigration` interdit (données utilisateur) ; écrire les `ALTER TABLE` à chaque ajout de colonne.

---

### 2. Synchronisation : `LibrarySyncService` → WorkManager + logique Kotlin

Logique exacte à reproduire (`Sync/LibrarySyncService.swift`) :

1. **Authentification** (`provider.authenticate()`), phase `authenticating`.
2. **Décision full vs delta** sur `server.hasCompletedInitialSync` :
   - **1ʳᵉ synchro** : `fetchLibrary()` (scan complet). **Le curseur est capturé AVANT le fetch** : `cursorStart = ISO8601 UTC de now`, puis après application `lastFullSyncDate = now`, `syncCursor = cursorStart`. Raison documentée : tout ajout serveur pendant le scan (potentiellement long) sera repris au prochain delta plutôt que manqué (recouvrement borné, upsert idempotent). **À conserver impérativement** côté Kotlin — c'est le point subtil.
   - **synchros suivantes** : `syncDelta(since: server.syncCursor)`, puis `if delta.newSyncCursor != nil { server.syncCursor = it }`.
3. `lastDeltaSyncDate = now`, save explicite (`if context.hasChanges`).
4. **Favoris serveur** (`applyServerFavorites`) : UNION stricte — on ne fait que **poser** `isFavorite = true` + `favoriteDate = now`, jamais retirer, jamais réécrire sur le serveur, jamais propager aux miroirs d'autres serveurs. Tolérant aux erreurs.
5. **Préchargement pochettes** (`prefetchArtwork`, voir §4).

Upserts (`upsertArtists/Albums/Tracks`) : idempotents, via un index mémoire `LibraryIndex` qui charge une fois tous les modèles du serveur (filtrés **en Swift** par préfixe `"<serverID>:"` — le `#Predicate starts(with:)` trappe à l'exécution dans SwiftData). Côté Room, ce contournement disparaît : on peut filtrer en SQL `WHERE serverId = :id` directement (ou `id LIKE :prefix || '%'`), donc l'index mémoire est optionnel — mais garder l'`@Upsert` (Room 2.5+) pour l'idempotence. Notification de progression limitée (`tick` tous les 25 éléments).

**Mapping Android :**

- **Provider/réseau** : remplacer la couche `ServerProvider` (acteurs Swift) par des interfaces Kotlin `suspend fun` + **Retrofit/OkHttp** (Jellyfin/Subsonic) et **DocumentFile/MediaStore** (local). DTOs `Sendable` (`LibrarySnapshot`, `SyncDelta`, `RemoteArtist/Album/Track`) → `data class` Kotlin (`@Serializable` kotlinx ou Moshi).
- **Orchestration** : la synchro déclenchée par l'utilisateur reste une coroutine sur `Dispatchers.IO` ; la synchro **en arrière-plan / périodique** passe par **WorkManager** (`CoroutineWorker`). Utiliser une `OneTimeWorkRequest` (synchro manuelle) et une `PeriodicWorkRequest` avec `Constraints(NetworkType.CONNECTED)`. `setUniqueWork(serverId, ExistingWorkPolicy.KEEP)` pour ne pas empiler deux synchros du même serveur.
- **Progression** : remonter via `setProgress(Data)` (Worker) observé par `WorkInfo` LiveData/Flow, en répliquant l'enum `Progress.Phase` (`authenticating`, `fetchingLibrary`, `fetchingDelta`, `applying`, `fetchingArtwork`, `done`) et `fraction = processed/total`.
- **Concurrence DB** : tout l'upsert dans une `@Transaction` Room (`withTransaction { }`), sur `Dispatchers.IO`. Pas besoin du `@MainActor` iOS (Room interdit l'accès UI thread par défaut).
- **Suppressions** : `delta.deleted*IDs` traités en ordre tracks → albums → artistes (évite les orphelins). Les providers actuels n'en signalent pas, mais garder le code prêt.

---

### 3. Téléchargements : `DownloadManager` (URLSession background) → Media3 `DownloadManager`

Comportement iOS (`Downloads/`) :

- `URLSession` **background** (`app.sillon.downloads`), `sessionSendsLaunchEvents = true`, reprise après suspension/relance. No-op pour serveurs `.local`. No-op si déjà `downloaded`/`downloading`/`queued`.
- Destination encodée dans `taskDescription = "<trackID>\u0001<destinationPath>"` (décodable sans SwiftData, y compris après relance). Le délégué non isolé déplace le fichier **synchronement** (sinon supprimé), puis `Task { @MainActor }` met à jour la base.
- **Agencement fichiers** (`DownloadFileLayout`) : `<racine>/<NomServeur>/<Artiste>/<Album>/<NN - Titre>.<ext>`, chaque composant `sanitize` (remplace `/\:*?"<>|` + caractères de contrôle par `_`, borne à 120 car, fallback `_`). `NN` = `%02d` du `trackNumber` si présent. Extension = `track.format` trimmé sinon `"audio"`. Racine iOS = `Documents/Downloads`, macOS = `Application Support/Sillon/Downloads`.
- `resolve(storedPath:)` rebranche un chemin absolu périmé (conteneur déplacé après MAJ OS) en repartant du suffixe relatif après `/Downloads/`.
- État dédoublé : `Track.downloadStatus` (résumé liste) **et** `DownloadTask` (détail reprise : `progressFraction` 0..1, `errorMessage`, `urlSessionTaskIdentifier`, `startedAt/completedAt`). `reconcileOnLaunch()` : un `DownloadTask` `downloading` sans tâche système vivante → si le fichier final existe, succès (`finalize`) ; sinon `failed` (« Téléchargement interrompu »).
- `localURL(for:)` : offline-first ; si la copie n'a pas de fichier local, cherche une copie du même titre sur un autre serveur (`DuplicateResolver.trackCopies`).

**Mapping Android :**

- **Moteur** : **Media3 `androidx.media3.exoplayer.offline.DownloadManager`** + **`DownloadService`** (Foreground Service, survit à l'app fermée — équivalent de la background URLSession). Construire chaque requête via `DownloadRequest.Builder(id, uri)` où `id = track.id` (la clé composite). `CacheWriter`/`HttpDataSource` gèrent la reprise (Range requests) nativement. `DownloadManager.addDownload`/`removeDownload`/`pauseDownloads`.
- **Persistance des téléchargements** : Media3 garde son propre index (`DefaultDownloadIndex` sur `StandaloneDatabaseProvider`). Deux options :
  1. Laisser Media3 gérer l'état + un `DownloadManager.Listener` (`onDownloadChanged`) qui recopie l'état dans la table Room `DownloadTask`/`Track.downloadStatus` (recommandé : garde l'UI et la réconciliation identiques à iOS).
  2. Implémenter un téléchargeur custom avec **WorkManager + OkHttp** (`Range` headers, `setForegroundAsync` pour le foreground service). Plus proche ligne-à-ligne de l'iOS (taskDescription, déplacement de fichier, finalize/markFailed) mais réinvente la reprise.
- **Agencement fichiers** : reproduire `DownloadFileLayout` à l'identique (même `sanitize`, même arborescence `<serveur>/<artiste>/<album>/<NN - titre>.<ext>`). Racine Android = `context.getExternalFilesDir(null)/Downloads` (ou `filesDir/Downloads` pour le privé). **Attention** : Media3 par défaut écrit dans un `Cache` opaque (noms de fragments) — pour conserver l'arborescence lisible « façon Sillon », préférer un téléchargeur custom OkHttp qui écrit directement aux chemins calculés, ou un post-traitement copiant hors du cache Media3.
- **Progression** : `DownloadManager.Listener.onDownloadChanged` expose `Download.getPercentDownloaded()` / `bytesDownloaded`. Mapper sur `DownloadTask.progressFraction`. États Media3 (`STATE_QUEUED`, `DOWNLOADING`, `COMPLETED`, `FAILED`, `STOPPED`) → `DownloadStatus` (`queued`/`downloading`/`downloaded`/`failed`/`notDownloaded`). Garder les mêmes `systemImageName` remplacés par des icônes Material (cloud download, schedule, check_circle, error).
- **Réconciliation au lancement** (`reconcileOnLaunch`) : Media3 la fait seul (reprend `DOWNLOADING` au redémarrage du service). Pour le cas custom, répliquer la logique « tâche fantôme → fichier présent = succès, sinon failed ».
- **Chemin périmé** (`resolve`) : moins critique sur Android (le `filesDir` est stable), mais garder un fallback reconstruisant depuis le suffixe relatif après `/Downloads/` reste prudent (sauvegarde/restauration, changement de stockage).

---

### 4. Cache de pochettes : `ArtworkCache` → Coil + cache disque

iOS (`Views/Shared/ArtworkCache.swift`, `actor`) :

- Une image par couple **(serverID, chemin distant)**, **résolution canonique 600 px** (couvre cartes ≤360 et lecteur 600 ; une seule taille pour maximiser la réutilisation). Downscale à l'affichage.
- Nom de fichier déterministe = **SHA-256 hex de `"<serverID.uuidString>|<path>"`** + extension `.img`.
- Dossier = `Caches/Artwork/` (purgeable par le système, reconstruit à la synchro suivante).
- Préchargement pendant la synchro (`prefetchArtwork`) : collecte les `coverArtRemotePath` uniques des albums du serveur **absents du cache**, résout les URLs (`coverArtURL(for:preferredSize:600)`), télécharge par **lots concurrents de 8** (`withTaskGroup`), stocke via `ArtworkCache.store`, remonte la progression (phase `fetchingArtwork`).

**Mapping Android :**

- **Bibliothèque** : **Coil 2.x** (`io.coil-kt`, Kotlin/Compose-natif ; `AsyncImage`). Configurer un `ImageLoader` applicatif avec `MemoryCache` + **`DiskCache`** (taille bornée, par défaut `cacheDir/image_cache`).
- **Clé de cache stable** : reproduire l'unicité (serveur, chemin). Passer une `ImageRequest` avec `.diskCacheKey(sha256("$serverId|$path"))` et `.memoryCacheKey(...)` — sinon Coil clive par URL (les URLs Jellyfin/Subsonic portent un jeton qui change, ce qui casserait la réutilisation, exactement la raison du hash iOS). Pour répliquer le `.img` SHA-256 à l'octet près si on veut un dossier partagé/portable, écrire un `Fetcher`/`Keyer` custom.
- **Taille canonique** : demander 600 px côté requête réseau (`coverArtURL(preferredSize=600)`) ; laisser Coil downscaler à l'affichage (`size(...)` ou modificateur Compose). Évite de stocker plusieurs tailles.
- **Préchargement à la synchro** : dans le `CoroutineWorker`, après l'upsert, énumérer les `coverArtRemotePath` distincts du serveur, filtrer ceux absents du `DiskCache` (`imageLoader.diskCache?.openSnapshot(key)`), puis précharger par lots concurrents (≈8) avec `imageLoader.execute(ImageRequest.Builder(...).build())` ou `enqueue`, en limitant via un `Semaphore(8)` dans un `coroutineScope { }`. Remonter la progression (phase `fetchingArtwork`).
- **Purge système** : `cacheDir` Android est purgeable comme `Caches/` iOS — comportement équivalent, reconstruit à la synchro suivante.

---

### 5. Localisation : `LanguageManager` (10 langues + changement à la volée) → strings.xml + per-app locale (AppCompat)

iOS (`Localization/LanguageManager.swift` + `Localizable.xcstrings`) :

- **Langues** (confirmé dans le String Catalog, `sourceLanguage: fr`, **199 clés**, **10 langues** présentes) : `de, en, es, fr, it, pt, rm, sq, sr, tr` + une option « Automatique » (`system`) suivant l'appareil. `AppLanguage.displayName` affiche chaque langue **en endonyme** (Français, Deutsch, Italiano, English, Português, Shqip, Español, Srpski, Rumantsch, Türkçe).
- **Changement à la volée SANS redémarrage** : astuce Objective-C runtime — `object_setClass(Bundle.main, LocalizedBundle.self)` puis `objc_setAssociatedObject` redirige `Bundle.main` vers le `.lproj` choisi ; `Text`, `Label`, `String(localized:)` passent tous par `localizedString(forKey:)`.
- `LanguageManager.string(key)` / `string(key, args...)` : passe-plat pour le texte hors `LocalizedStringKey` (labels d'enum, messages d'erreur) — il suit la langue **choisie**, pas la langue système. Utilisé partout (`DownloadStatus.label`, `ServerType.displayName`, `EQMode.label`, message « Téléchargement interrompu »…). `locale` injectée dans l'environnement SwiftUI pour formats dates/nombres.

**Mapping Android :**

- **Ressources** : un fichier `res/values-<lang>/strings.xml` par langue : `values/` (fr, défaut, = sourceLanguage), `values-de`, `values-en`, `values-es`, `values-it`, `values-pt`, `values-rm` (romanche — code BCP-47 `rm`, supporté ; si un device l'ignore, fallback défaut), `values-sq`, `values-sr`, `values-tr`. **Convertir le `.xcstrings`** (JSON, 199 clés) en strings.xml : extraire chaque clé+traduction par langue ; les clés iOS sont les chaînes françaises elles-mêmes → en Android, créer des **noms de ressources stables** (`R.string.xxx`) et mapper. Spécificateurs de format `%@`→`%s`, `%lld`/`%d`→`%d`, `%%`→`%%`. Les variantes plurielles (ex. `%lld album%@`, `%lld titre%@`) → **`<plurals>`** (`quantityString`) plutôt que concaténation.
- **Changement de langue à la volée** : **per-app language** via **AppCompat 1.6+** `AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags("de"))`. C'est l'équivalent natif et propre du hack de bundle iOS : recrée les activités avec la nouvelle locale sans relancer le process. Sur Android 13+ (API 33), c'est géré par le système (Settings ▸ App languages) ; AppCompat backporte automatiquement < API 33 (déclarer `LocaleConfig` dans le manifest + `service` AppLocalesMetadataHolderService). « Automatique » = `LocaleListCompat.getEmptyLocaleList()` (suit le système).
- **Persistance du choix** : AppCompat le persiste seul (< API 33) / le système le retient (≥ API 33). L'équivalent du `UserDefaults "appLanguage"` n'est plus nécessaire, mais on peut garder une copie pour l'UI du sélecteur.
- **Texte hors Compose statique / enums** : pas besoin de l'équivalent `LanguageManager.string` — `context.getString(R.string.x)` (ou `stringResource(R.string.x)` en Compose) suit déjà la per-app locale. Pour du code sans `Context` (couche modèle), injecter un `Context` localisé (`createConfigurationContext(config)`) ou remonter ces libellés dans la couche UI.
- **Formats dates/nombres** : la per-app locale propage `Locale.getDefault()` ; utiliser `java.time` + `DateTimeFormatter.ofLocalizedDate(...).withLocale(locale)` — équivalent du `LanguageManager.locale` injecté.

---

### 6. Traduction des paroles : Apple Translation + NaturalLanguage → ML Kit Translation + ML Kit Language ID

iOS (`Views/Player/LyricsView.swift`, paroles via `LyricsLoader` → DTO `TrackLyrics { synced: Bool, lines: [LyricLine{ timeSeconds: Double?, text: String }] }`) :

- **Détection de langue** : `NaturalLanguage` → `NLLanguageRecognizer().processString(text)` sur la concaténation des lignes ; `dominantLanguage?.rawValue` (code BCP-47, ex. `"en"`, `"fr"`). Stocké dans `detectedLanguage`.
- **Traduction** : framework **`Translation`** d'Apple, **sur l'appareil, gratuit, sans clé ni envoi réseau des paroles**. `.translationTask(config)` + `TranslationSession.translations(from: [Request(sourceText, clientIdentifier: String(index))])` → réponses `targetText` ré-indexées par `clientIdentifier` dans `[Int: String]`. Modèle de langue téléchargé à la demande (invite système la 1ʳᵉ fois) ; échec/refus → on garde l'original et on remet `config = nil` pour permettre un nouvel essai.
- **Garde-fou** (`canTranslate`) : bouton « Traduire » affiché **seulement si** langue source détectée ET langue cible (= langue de l'app, ou langue device si « Automatique ») sont toutes deux dans **`{de, fr, it, es, en}`** ET **différentes** (paroles déjà dans la langue de l'app → pas de bouton). Cible = `LanguageManager.current.localeCode` sinon `Locale.current.language.languageCode`.
- UI : sous chaque ligne, traduction affichée en vert (`Palette.signalTeal`) ; bouton bascule « Traduire »/« Original ».

**Mapping Android :**

- **Détection de langue** : **ML Kit Language Identification** (`com.google.mlkit:language-id`), sur l'appareil, gratuit. `LanguageIdentification.getClient().identifyLanguage(text)` → code BCP-47 (`"en"`, `"fr"`, ou `"und"` si indéterminé). Équivalent direct de `NLLanguageRecognizer.dominantLanguage`. Construire le `text` comme iOS : `lines.joinToString("\n") { it.text }`, ignorer si vide.
- **Traduction** : **ML Kit Translation** (`com.google.mlkit:translate`), **sur l'appareil, gratuit, sans clé**. Pipeline :
  1. `TranslatorOptions.Builder().setSourceLanguage(TranslateLanguage.fromLanguageTag(source)).setTargetLanguage(...).build()` → `Translation.getClient(options)`.
  2. **Téléchargement conditionnel du modèle** : `translator.downloadModelIfNeeded(DownloadConditions.Builder().requireWifi().build())` — équivalent de l'invite/téléchargement à la demande iOS. Sur échec (pas de réseau / refus), garder l'original (comme le `catch` iOS qui remet `config = nil`).
  3. Traduire **ligne par ligne** en gardant l'index : pour chaque `LyricLine` non vide, `translator.translate(line.text)` (Task) → remplir `Map<Int, String>` (clé = index de ligne, exactement le `clientIdentifier`/`Int` iOS). Lancer en parallèle borné (coroutines + `await` sur les `Task` via `kotlinx-coroutines-play-services`).
  4. **Libérer** : `translator.close()` quand l'écran de paroles se ferme (les modèles ML Kit tiennent des ressources natives).
- **Garde-fou `canTranslate`** : reproduire à l'identique. Cible = per-app locale (`AppCompatDelegate.getApplicationLocales()[0]?.language`) sinon `Locale.getDefault().language`. Source = résultat ML Kit ID. Afficher le bouton seulement si source ∈ `{de, fr, it, es, en}`, cible ∈ `{de, fr, it, es, en}`, et `source != cible`. **Note** : ML Kit supporte ~50+ langues (dont les 5), donc l'ensemble pourrait être élargi plus tard sans contrainte technique — garder `{de, fr, it, es, en}` pour la parité iOS exacte.

**Mapping des codes langue** (iOS ↔ ML Kit) : ML Kit utilise `TranslateLanguage` (constantes BCP-47). `TranslateLanguage.fromLanguageTag("fr"|"de"|"it"|"es"|"en")` couvre les 5 ciblées. Le code renvoyé par ML Kit Language ID est déjà BCP-47, compatible direct avec `fromLanguageTag`. Les 10 langues d'UI ne sont pas toutes traductibles (rm = romanche **non** supporté par ML Kit Translation, sq/sr/pt/tr non inclus dans l'ensemble {de,fr,it,es,en} retenu côté iOS de toute façon) — le garde-fou `canTranslate` masque proprement le bouton dans ces cas, comportement identique à l'iOS.

- UI Compose : sous chaque `Text(line.text)`, un `Text(translation)` coloré (équivalent `signalTeal`) quand `showTranslation`. Pour les paroles synchronisées, conserver la logique `activeLineIndex(at: currentTime)` (`TrackLyrics.activeLineIndex`, ProviderModels.swift) côté lecteur Media3 (`player.currentPosition`).

---

Fichiers iOS de référence (chemins absolus) :
- Modèles : `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Models/{Track,Album,Artist,Playlist,ServerAccount,DownloadTask,DownloadStatus,EQSettings,EQPreset}.swift`, schéma `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Persistence/ModelContainerFactory.swift`
- Synchro : `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Sync/LibrarySyncService.swift`
- Téléchargements : `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Downloads/{DownloadManager,DownloadFileLayout,DownloadSessionDelegate}.swift`
- Cache pochettes : `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Views/Shared/ArtworkCache.swift`
- Localisation : `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Localization/LanguageManager.swift`, `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Localizable.xcstrings`
- Paroles/traduction : `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Views/Player/LyricsView.swift`, `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Views/Shared/LyricsLoader.swift`, DTO `/Users/thomaskohler/_DEV/Github/Sillon/Sillon/Networking/ProviderModels.swift`