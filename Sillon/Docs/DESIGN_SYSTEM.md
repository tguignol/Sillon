# Système de design — Sillon

Brief : app de lecture musicale connectée à des serveurs personnels (Jellyfin, Navidrome/Subsonic,
fichiers locaux). Public : audiophiles qui auto-hébergent leur musique — exigeants sur le son
(d'où l'EQ libre, le "pas de transcodage"), mais qui veulent une UI aussi soignée qu'Apple Music,
pas un outil austère façon Symfonium. Job de l'écran d'accueil : donner immédiatement la sensation
"voici votre disquaire personnel", pas "voici un client API".

## Tension fondatrice

Le sujet a une vraie dualité : la chaleur analogique du vinyle/de la hi-fi vs la précision technique
de l'infrastructure serveur (codecs, bitrate, sync delta). Le système de design exploite cette tension
plutôt que de la gommer : chaleur cuivrée pour tout ce qui est musique/cover art, froid technique
(monospace, teal) réservé aux données — bitrate, codec, horodatages de sync, valeurs dB de l'EQ.

## Palette (4-6 teintes nommées)

| Nom | Hex | Usage |
|---|---|---|
| `fond.noir` | `#0B0D0F` | Fond principal (dark natif, pas un gris neutre — légèrement bleuté froid) |
| `surface.elevee` | `#15181B` | Cartes, feuilles modales, lignes de liste survolées |
| `accent.cuivre` | `#D98E4A` | Accent principal : cœur favori, lecture en cours, AccentColor système |
| `signal.teal` | `#4FA8A0` | Réservé aux données techniques : EQ actif, indicateur de sync, badges codec |
| `texte.ivoire` | `#F3F1EC` | Texte principal (blanc cassé chaud, pas blanc pur — évoque le papier de pochette) |
| `texte.sourdine` | `#9A9590` | Texte secondaire, légendes, métadonnées |

Décision : pas de rouge/rose façon Apple Music, pas de vert façon Spotify — le cuivre évite les deux
clichés du genre tout en restant chaleureux sur fond noir.

## Typographie (2 rôles + 1 utilitaire)

- **Display** (titres d'album, nom d'artiste en grand sur l'écran lecteur) :
  `Font.system(.title, design: .serif)` — empattement système, du caractère sans dépendance externe.
- **Corps / UI** (listes, boutons, labels) : `Font.system(.body, design: .default)` — SF Pro, neutre et lisible.
- **Utilitaire technique** (bitrate, codec, dB de l'EQ, horodatage de sync) :
  `Font.system(.caption, design: .monospaced)` — signale visuellement "ceci est une donnée technique",
  distinct du reste de l'UI.

Décision documentée : aucune police tierce embarquée pour rester sans dépendance externe non validée.
Si une police de marque est souhaitée plus tard, ce sera proposé explicitement (item de polish visuel),
pas ajouté silencieusement.

## Layout — signature

- Accueil façon "bac à disques" : sections horizontales (Ajouts récents, Favoris récents, Playlists)
  mais avec des tailles de carte volontairement inégales (les ajouts récents en grand format,
  favoris/playlists en format réduit) plutôt qu'une grille parfaitement uniforme — évite l'effet
  "grille Apple Music clonée".
- Écran lecteur : un fin anneau ("groove ring") entoure la pochette et trace la progression de lecture,
  en écho discret au sillon d'un vinyle — en complément (pas en remplacement) de la barre de
  progression avec -10s/+10s intégrés exigée par le brief. C'est l'élément signature de l'app.
- Densité : sobre/premium veut dire précision dans l'espacement plutôt que minimalisme vide —
  on suit l'esthétique "exécution soignée d'une direction simple", pas une absence de direction.

## Composants à dériver de ces tokens (prochains commits UI)

Un fichier `DesignSystem.swift` (couleurs, polices, espacements en tant que constantes Swift)
sera introduit au commit où la première vraie vue est construite (Gestion des serveurs), pour que
toute l'UI dérive de ce système plutôt que de valeurs ad hoc dispersées dans les vues.
