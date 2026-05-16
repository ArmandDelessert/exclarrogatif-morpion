# Morpion exclarrogatif - Message caché

Tout a commencé avec la vidéo [**Affrontez-moi au morpion !**](https://www.youtube.com/watch?v=UnDjokbZjbs) de la chaîne [**exclarrogatif**](https://www.youtube.com/@exclarrogatif). Le concept : un morpion (tic-tac-toe) entièrement jouable via les écrans de fin YouTube. Chaque vidéo propose plusieurs choix qui mènent à d'autres vidéos, formant un graphe d'environ 150 vidéos interconnectées.

En regardant attentivement, on remarque qu'un tableau blanc en arrière-plan affiche à chaque vidéo un **nombre** et une **lettre** en aimants magnétiques. Intrigant. Et si ces indices, mis bout à bout dans l'ordre des nombres, formaient un message ?

Pour le découvrir, il fallait d'abord explorer l'intégralité du graphe, capturer une image de chaque vidéo, puis extraire et ordonner les 131 indices. Un travail fastidieux à la main... mais pas avec les bons outils.

## Méthode

1. **Parcours du graphe** : exploration BFS des écrans de fin et des liens en description pour découvrir toutes les vidéos de la série.
2. **Capture de frames** : extraction d'images à des timestamps précis via `yt-dlp` + `ffmpeg` (seek côté serveur, sans télécharger la vidéo entière).
3. **Recadrage** : extraction de la zone du tableau blanc par crop ffmpeg.
4. **OCR via Claude** : envoi des images recadrées à l'API Claude (vision) pour extraire nombre + lettre.
5. **Correction manuelle** : interface web locale pour vérifier et corriger les résultats de l'OCR.
6. **Reconstitution** : tri par nombre et concaténation des lettres.

## Graphe des vidéos

Le graphe complet au format DOT et SVG est inclus dans le dépôt. Les noeuds du SVG sont cliquables et mènent vers les vidéos YouTube correspondantes.

- [`exclarogatif-morpion-video-graph.dot`](exclarogatif-morpion-video-graph.dot) - Format Graphviz DOT
- [`exclarogatif-morpion-video-graph.svg`](exclarogatif-morpion-video-graph.svg) - Rendu SVG interactif (généré via [Edotor](https://edotor.net/))

## Scripts

### Prérequis

- **PowerShell 5.1+** (inclus dans Windows)
- **Python 3.10+** avec `pip install anthropic pillow`
- [**yt-dlp**](https://github.com/yt-dlp/yt-dlp) dans le PATH
- [**ffmpeg**](https://ffmpeg.org/) dans le PATH
- Variable d'environnement `ANTHROPIC_API_KEY` pour l'extraction OCR

### Get-YouTubeGraph.ps1

Parcourt les écrans de fin et les descriptions des vidéos YouTube par BFS pour générer un graphe (DOT, CSV ou liste).

```powershell
# Graphe DOT depuis la vidéo de départ
.\Get-YouTubeGraph.ps1 -StartVideoId "UnDjokbZjbs" -OutputFormat GraphDOT > graph.dot

# Limiter au même channel, profondeur max 3
.\Get-YouTubeGraph.ps1 -StartVideoId "UnDjokbZjbs" -OnlySameChannel -MaxDepth 3

# Avec cookies pour éviter le blocage anti-bot
.\Get-YouTubeGraph.ps1 -StartVideoId "UnDjokbZjbs" -CookiesFile cookies.txt

# Exclure des vidéos déjà visitées
.\Get-YouTubeGraph.ps1 -StartVideoId "UnDjokbZjbs" -ExcludeFile already-visited.txt
```

Sources de liens extraites :

- `endscreenElementRenderer` : écrans de fin configurés par le créateur
- `structuredDescriptionVideoLockupRenderer` : vidéos intégrées dans la description

### Get-YouTubeFrames.ps1

Capture une ou plusieurs frames de chaque vidéo YouTube sans télécharger la vidéo entière.

```powershell
# Capture basique (frame à t=0)
.\Get-YouTubeFrames.ps1 -InputFile videos.txt -OutputDir frames

# Plusieurs timestamps, résolution 1080p
.\Get-YouTubeFrames.ps1 -InputFile videos.txt -OutputDir frames -SeekSeconds 0,1.5,3 -MaxHeight 1080

# Ignorer les captures existantes + cookies
.\Get-YouTubeFrames.ps1 -InputFile videos.txt -OutputDir frames -SkipExisting -CookiesFile cookies.txt
```

Le fichier d'entrée contient un identifiant de vidéo par ligne (format TSV supporté).

### Crop-Images.ps1

Recadre un lot d'images à l'aide de ffmpeg.

```powershell
.\Crop-Images.ps1 -InputDir frames -OutputDir frames_crop -Width 400 -Height 320 -X 70 -Y 288
```

### Extract-Indices.py

Envoie chaque image recadrée à l'API Claude (vision) pour extraire le nombre et la lettre.

```bash
python Extract-Indices.py frames_crop indices.csv
```

Produit un CSV avec les colonnes : `video_id`, `filename`, `number`, `letter`, `raw`.

### Review-Indices.py

Interface web locale pour corriger les résultats de l'OCR. Pré-remplit les champs depuis le CSV existant.

```bash
python Review-Indices.py frames_crop indices.csv
# Ouvre http://localhost:8080
```

Raccourcis clavier : `Entrée` (suivant), `Shift+Entrée` (précédent), `Alt+N` (nombre), `Alt+L` (lettre), `Alt+X` (pas de code), `Ctrl+S` (sauvegarder).

## Tableau des indices

| ID de vidéo | Nombre | Lettre |
| ----------- | ------ | ------ |
| `jgEbvhS80JM` |   1 | F |
| `srKXPMS6EJ4` |   2 | E |
| `GViqPBT0EGc` |   3 | L |
| `_u8KSgM-Ok4` |   4 | I |
| `rkOoOqEwMIQ` |   5 | C |
| `D31ufAb7I_Y` |   6 | I |
| `k39jYoLgY5E` |   7 | T |
| `ASlxa7x8g0I` |   8 | A |
| `aT7dUdeKs2U` |   9 | T |
| `wv31xd90x8w` |  10 | I |
| `Nybqs50bPQo` |  11 | O |
| `gPVtnXTuCjw` |  12 | N |
| `8wwb01iwCYI` |  13 | S |
| `f2DVcc8nVFk` |  14 | V |
| `Ce_k5E5ifW4` |  15 | O |
| `yQiJM3_rpAo` |  16 | U |
| `lM_oCWjubuQ` |  17 | S |
| `Fr_yt3N3W7I` |  18 | A |
| `Uc0QxNu6BsI` |  19 | V |
| `0eBtlba_3yI` |  20 | E |
| `4fAkgc--IWQ` |  21 | Z |
| `Xho5WcL5V7g` |  22 | P |
| `FtrtLZgbAQk` |  23 | A |
| `clZpXNLZJ-I` |  24 | S |
| `xz0VzzVh4Hk` |  25 | S |
| `LE5PWGkolXg` |  26 | E |
| `j4fn51CfwIc` |  27 | T |
| `2B2_LtBK-QQ` |  28 | R |
| `KTJJjTql-5o` |  29 | O |
| `OPhrkuoPyHk` |  30 | P |
| `T7ik67qfYVQ` |  31 | D |
| `4gRai8MIuAY` |  32 | E |
| `WlVbSyH5iTY` |  33 | T |
| `RZ1s1apAV-s` |  34 | E |
| `8otqvHAExrc` |  35 | M |
| `acm9iqAA7Vc` |  36 | P |
| `s_6Sx9sQQrw` |  37 | S |
| `GhnaCRAcboM` |  38 | A |
| `8EWo8cwGgUU` |  39 | R |
| `GaPEymEw7T0` |  40 | E |
| `z9Ga7BeEAJk` |  41 | G |
| `n1_wxuBh7J8` |  42 | A |
| `hFfEyuhO0Ls` |  43 | R |
| `54gc1STymz4` |  44 | D |
| `pOak4ISlG1Y` |  45 | E |
| `MdJNMn-4v_g` |  46 | R |
| `hH-Up6PctDQ` |  47 | M |
| `zonpHSNVppY` |  48 | E |
| `4_jcEhlSFHA` |  49 | S |
| `5v00E4RE9Cw` |  50 | V |
| `W6-ZZ0vtgnc` |  50 | V |
| `Ta7deZ0gunQ` |  51 | I |
| `fgTC4JEJsGA` |  52 | D |
| `GjQhRWOdgL4` |  53 | E |
| `uCOwuqiuqPw` |  54 | O |
| `gDp1QPFbcnk` |  55 | S |
| `m-K9aOjQZkA` |  56 | E |
| `hkYpsr9T0j8` |  57 | N |
| `EaNca2j6qWY` |  58 | V |
| `_a-YoU0uals` |  59 | O |
| `BKcKzhWRnzs` |  60 | Y |
| `quT8maGtQFM` |  61 | E |
| `NEE8o5Q6Rkk` |  62 | Z |
| `zig6bu8xtUs` |  63 | M |
| `2QsyD5GWGnM` |  64 | O |
| `E4Y4fVDH2xg` |  65 | I |
| `dzktMMgs5v4` |  66 | U |
| `vQ4DPkdZvwQ` |  67 | N |
| `obVLX-9i3Y4` |  68 | M |
| `b9PaDptesqg` |  69 | A |
| `NTCptCs0q7o` |  70 | I |
| `dY_ZKGHeN8Q` |  71 | L |
| `vCR_U7fCNwI` |  72 | A |
| `qwc-R6VZbTA` |  73 | V |
| `KT5kVqtCOzg` |  74 | E |
| `iVWiiaM4ewc` |  75 | C |
| `XrZBsD34qj4` |  76 | L |
| `TRCq7xeFTMk` |  77 | E |
| `pI3PjEv7EjU` |  78 | M |
| `lCIranADf9Y` |  79 | O |
| `USxiJQSh9ow` |  80 | T |
| `FNBIM48DI5c` |  81 | D |
| `WAu74TcqNZA` |  82 | E |
| `8rkyAPrJhYE` |  83 | P |
| `JyC6RJQ3PWY` |  84 | A |
| `-N5KaqP05wA` |  85 | S |
| `2YMyrFuwo9Y` |  86 | S |
| `Y4RfqqdY-jM` |  87 | E |
| `bDmHGdHSb2Y` |  88 | S |
| `dnVjQbYSp7A` |  89 | C |
| `HfvHF9hoJT0` |  90 | N |
| `X4WH-ZaBspk` |  91 | M |
| `taFsGCNbxiw` |  92 | I |
| `ihHkeCO8Dl8` |  93 | L |
| `CognvkVPmPA` |  94 | B |
| `Ar1-1upOz-A` |  95 | L |
| `eisjXWCm-4E` |  96 | I |
| `qyg_HQjqFb4` |  97 | C |
| `YLmydj19cek` |  98 | K |
| `rMF1YvD29ww` |  99 | E |
| `IDxR4G7DSig` | 100 | T |
| `v5_yNLUB2rI` | 101 | G |
| `1b6G4gyD4N0` | 102 | A |
| `VHO44NGxZAs` | 103 | G |
| `S3OJ7wk3sUw` | 104 | N |
| `0aQL9jfSPdc` | 105 | E |
| `FZGEIdV3uj0` | 106 | Z |
| `DhYkpHEvpek` | 107 | M |
| `hM3iD_wibyE` | 108 | A |
| `CMrUSAbY5K4` | 109 | R |
| `JGfc0UGiqmA` | 110 | E |
| `-cPNSN-reLc` | 111 | C |
| `-92TTcbPvHA` | 112 | O |
| `l2sJq_iBPeE` | 113 | N |
| `O8Mpt05cLc8` | 114 | N |
| `VvnxfMq_0x0` | 115 | A |
| `L6uK4lSdafc` | 116 | I |
| `UREboB8FcKw` | 117 | S |
| `dTeI1JXNtiY` | 118 | S |
| `SvnZDAyBOSk` | 119 | A |
| `nWbIpmn9lsg` | 120 | N |
| `Jrb8hQBppxg` | 121 | C |
| `N_cTpyxL15Q` | 122 | E |
| `RaVErDpH5Cg` | 123 | E |
| `8rYwvoJRpug` | 124 | T |
| `bVyQxzI1Dqo` | 125 | E |
| `rWiNZd1WSVE` | 126 | R |
| `cdFookHj08A` | 127 | N |
| `yeY-cW78hRw` | 128 | E |
| `plJ554i9pIw` | 129 | L |
| `Sb-n3JB7YME` | 130 | L |
| `8EHRSTAyUY0` | 131 | E |

> **Note** : les vidéos `5v00E4RE9Cw` et `W6-ZZ0vtgnc` portent toutes deux l'indice "50 V" (probablement un oubli de modification du talbeau entre les 2 vidéos). 8 vidéos du graphe ne contiennent aucun code sur le tableau (`58X2c66QxPs`, `65tS5PY8LdU`, `9J3nwusXamY`, `RyvWYc7Fp-U`, `tXYhgZ_rXs8`, `UnDjokbZjbs`, `zAy6U8A7kBo`, `ZFCxZMLZrpA`).

## Message caché

En ordonnant les 131 lettres par leurs nombres, on obtient :

> Félicitations vous avez passé trop de temps a regarder mes vidéos envoyez moi un mail avec le mot de passe `SCNMILBLICK` et gagnez ma reconnaissance éternelle.

## Licence

Ce dépôt contient uniquement les scripts d'analyse. Les vidéos sont la propriété d'[exclarrogatif](https://www.youtube.com/@exclarrogatif).
