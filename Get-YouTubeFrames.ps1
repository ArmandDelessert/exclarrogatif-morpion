<#
.SYNOPSIS
    Capture une ou plusieurs images (frames) de chaque vidéo YouTube à partir d'une liste d'identifiants.

.DESCRIPTION
    Utilise yt-dlp pour obtenir l'URL directe du flux vidéo, puis ffmpeg pour extraire
    une frame à chaque timestamp donné. Seules quelques secondes de vidéo sont téléchargées
    grâce au seek côté serveur (HTTP range request).

    Lorsque plusieurs timestamps sont spécifiés, l'URL du flux est récupérée une seule
    fois par vidéo, ce qui est nettement plus rapide que de relancer le script plusieurs fois.

    Les captures sont nommées selon le format : <videoId>_<timestamp>s.jpg
    Ce nommage permet de distinguer les captures à différents timestamps.

.PARAMETER InputFile
    Chemin vers un fichier texte contenant un identifiant de vidéo par ligne.
    Les lignes vides et les lignes commençant par # sont ignorées.
    Si le fichier est au format TSV (ID<tab>titre), seul le premier champ est utilisé.

.PARAMETER OutputDir
    Répertoire de sortie pour les captures. Créé automatiquement si inexistant.

.PARAMETER SeekSeconds
    Un ou plusieurs timestamps en secondes auxquels capturer les images.
    Accepte des valeurs décimales (ex: 0, 1.5, 3).
    Par défaut : 0 (première frame).

.PARAMETER MaxHeight
    Hauteur maximale du flux vidéo à utiliser (par défaut 720).
    Utiliser une valeur plus élevée (1080, 1440, 2160) pour une meilleure définition.

.PARAMETER DelayMs
    Délai en millisecondes entre chaque vidéo (par défaut 500ms).

.PARAMETER SkipExisting
    Si spécifié, ignore les captures qui existent déjà dans le répertoire de sortie.
    La vérification est faite par timestamp : si une vidéo a déjà une capture à 0s
    mais pas à 1.5s, seule la capture à 1.5s sera effectuée.

.PARAMETER CookiesBrowser
    Nom du navigateur depuis lequel extraire les cookies YouTube (ex: edge, chrome, firefox).
    Nécessaire lorsque YouTube bloque les requêtes non authentifiées.
    Le navigateur doit être fermé pour que yt-dlp puisse lire la base de cookies.

.PARAMETER CookiesFile
    Chemin vers un fichier cookies au format Netscape, comme alternative à -CookiesBrowser
    si le navigateur ne peut pas être fermé.

.EXAMPLE
    .\Get-YouTubeFrames.ps1 -InputFile videos.txt -OutputDir frames
    .\Get-YouTubeFrames.ps1 -InputFile videos.txt -OutputDir frames -MaxHeight 1080
    .\Get-YouTubeFrames.ps1 -InputFile videos.txt -OutputDir frames -SeekSeconds 0,1.5,5
    .\Get-YouTubeFrames.ps1 -InputFile videos.txt -OutputDir frames -CookiesBrowser edge
    .\Get-YouTubeFrames.ps1 -InputFile videos.txt -OutputDir frames -CookiesFile cookies.txt
#>
param (
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [double[]]$SeekSeconds = @(0),

    [int]$MaxHeight = 720,

    [int]$DelayMs = 500,

    [switch]$SkipExisting,

    [string]$CookiesBrowser,

    [string]$CookiesFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Vérification des dépendances
foreach ($tool in @("yt-dlp", "ffmpeg")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Error "$tool n'est pas installé ou n'est pas dans le PATH."
        exit 1
    }
}

# Construction des arguments cookies pour yt-dlp
$ytdlpCookieArgs = @()
if ($CookiesBrowser) {
    $ytdlpCookieArgs = @("--cookies-from-browser", $CookiesBrowser)
}
elseif ($CookiesFile) {
    if (-not (Test-Path $CookiesFile)) {
        Write-Error "Le fichier cookies '$CookiesFile' n'existe pas."
        exit 1
    }
    $ytdlpCookieArgs = @("--cookies", $CookiesFile, "--no-cookies-update")
}

# Lecture du fichier d'entrée
if (-not (Test-Path $InputFile)) {
    Write-Error "Le fichier d'entrée '$InputFile' n'existe pas."
    exit 1
}

$lines = Get-Content -Path $InputFile -Encoding UTF8
$videoIds = [System.Collections.Generic.List[string]]::new()

foreach ($line in $lines) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed.StartsWith("#")) {
        continue
    }
    # Support du format TSV (ID<tab>titre) : on prend le premier champ
    $id = ($trimmed -split "`t")[0].Trim()
    if ($id -ne "") {
        $videoIds.Add($id)
    }
}

if ($videoIds.Count -eq 0) {
    Write-Error "Aucun identifiant de vidéo trouvé dans '$InputFile'."
    exit 1
}

# Création du répertoire de sortie
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$timestampTags = $SeekSeconds | ForEach-Object { $_.ToString("0.##").Replace(",", ".") }
$timestampDisplay = ($timestampTags | ForEach-Object { "${_}s" }) -join ", "

Write-Host "Capture de $($videoIds.Count) vidéo(s) x $($SeekSeconds.Count) timestamp(s) ($timestampDisplay)" -ForegroundColor Cyan
Write-Host "Résolution max : ${MaxHeight}p" -ForegroundColor Cyan
Write-Host "Répertoire de sortie : $OutputDir" -ForegroundColor Cyan
Write-Host ""

$succeeded = 0
$skipped = 0
$failed = 0

for ($i = 0; $i -lt $videoIds.Count; $i++) {
    $videoId = $videoIds[$i]
    $index = $i + 1

    # Déterminer quels timestamps restent à capturer
    $pendingTimestamps = [System.Collections.Generic.List[int]]::new()
    for ($t = 0; $t -lt $SeekSeconds.Count; $t++) {
        $tag = $timestampTags[$t]
        $outputFile = Join-Path $OutputDir "${videoId}_${tag}s.jpg"
        if ($SkipExisting -and (Test-Path $outputFile)) {
            $skipped++
        }
        else {
            $pendingTimestamps.Add($t)
        }
    }

    if ($pendingTimestamps.Count -eq 0) {
        Write-Host "[$index/$($videoIds.Count)] $videoId -> toutes les captures existent, ignoré" -ForegroundColor DarkYellow
        continue
    }

    Write-Host "[$index/$($videoIds.Count)] $videoId" -ForegroundColor Gray -NoNewline

    # Récupérer l'URL directe du flux vidéo (une seule fois par vidéo)
    try {
        $ytdlpArgs = @("--get-url", "-f", "bv*[height<=${MaxHeight}]") + $ytdlpCookieArgs + @("https://www.youtube.com/watch?v=$videoId")
        $streamUrl = & yt-dlp @ytdlpArgs 2>$null
        if ([string]::IsNullOrWhiteSpace($streamUrl)) {
            Write-Host " -> ERREUR: yt-dlp n'a retourné aucune URL" -ForegroundColor Red
            $failed += $pendingTimestamps.Count
            continue
        }
    }
    catch {
        Write-Host " -> ERREUR yt-dlp: $_" -ForegroundColor Red
        $failed += $pendingTimestamps.Count
        continue
    }

    # Extraire une frame pour chaque timestamp
    $results = @()
    foreach ($t in $pendingTimestamps) {
        $seek = $SeekSeconds[$t]
        $tag = $timestampTags[$t]
        $outputFile = Join-Path $OutputDir "${videoId}_${tag}s.jpg"

        try {
            $ffmpegArgs = @(
                "-ss", "$seek",
                "-i", "$streamUrl",
                "-frames:v", "1",
                "-q:v", "2",
                "-update", "1",
                "-y",
                "$outputFile"
            )
            $ffmpegOutput = & ffmpeg @ffmpegArgs 2>&1
            if (Test-Path $outputFile) {
                $size = (Get-Item $outputFile).Length
                $results += "${tag}s OK ($('{0:N0}' -f ($size / 1KB)) Ko)"
                $succeeded++
            }
            else {
                $results += "${tag}s ERREUR"
                $failed++
            }
        }
        catch {
            $results += "${tag}s ERREUR: $_"
            $failed++
        }
    }

    Write-Host " -> $($results -join ' | ')" -ForegroundColor Green

    if ($i -lt $videoIds.Count - 1 -and $DelayMs -gt 0) {
        Start-Sleep -Milliseconds $DelayMs
    }
}

Write-Host ""
Write-Host "--- RÉSULTATS ---" -ForegroundColor Green
Write-Host "Réussies : $succeeded" -ForegroundColor Green
if ($skipped -gt 0) {
    Write-Host "Ignorées : $skipped" -ForegroundColor DarkYellow
}
if ($failed -gt 0) {
    Write-Host "Échouées : $failed" -ForegroundColor Red
}
