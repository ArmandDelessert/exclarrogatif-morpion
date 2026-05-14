<#
.SYNOPSIS
    Capture une image (frame) de chaque vidéo YouTube à partir d'une liste d'identifiants.

.DESCRIPTION
    Utilise yt-dlp pour obtenir l'URL directe du flux vidéo, puis ffmpeg pour extraire
    une frame à un timestamp donné. Seules quelques secondes de vidéo sont téléchargées
    grâce au seek côté serveur (HTTP range request).

    Les captures sont nommées selon le format : <videoId>_<timestamp>s.jpg
    Ce nommage permet de relancer le script avec un timestamp différent sans écraser
    les captures précédentes.

.PARAMETER InputFile
    Chemin vers un fichier texte contenant un identifiant de vidéo par ligne.
    Les lignes vides et les lignes commençant par # sont ignorées.
    Si le fichier est au format TSV (ID<tab>titre), seul le premier champ est utilisé.

.PARAMETER OutputDir
    Répertoire de sortie pour les captures. Créé automatiquement si inexistant.

.PARAMETER SeekSeconds
    Timestamp en secondes auquel capturer l'image (par défaut 0 = première frame).

.PARAMETER MaxHeight
    Hauteur maximale du flux vidéo à utiliser (par défaut 720).

.PARAMETER DelayMs
    Délai en millisecondes entre chaque capture (par défaut 500ms).

.PARAMETER SkipExisting
    Si spécifié, ignore les vidéos dont la capture existe déjà dans le répertoire de sortie.

.EXAMPLE
    .\Get-YouTubeFrames.ps1 -InputFile videos.txt -OutputDir frames
    .\Get-YouTubeFrames.ps1 -InputFile videos.txt -OutputDir frames -SeekSeconds 5
    .\Get-YouTubeFrames.ps1 -InputFile videos.txt -OutputDir frames -SkipExisting
#>
param (
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [double]$SeekSeconds = 0,

    [int]$MaxHeight = 720,

    [int]$DelayMs = 500,

    [switch]$SkipExisting
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

Write-Host "Capture de $($videoIds.Count) vidéos (seek: ${SeekSeconds}s, résolution max: ${MaxHeight}p)..." -ForegroundColor Cyan
Write-Host "Répertoire de sortie : $OutputDir" -ForegroundColor Cyan
Write-Host ""

$succeeded = 0
$skipped = 0
$failed = 0

for ($i = 0; $i -lt $videoIds.Count; $i++) {
    $videoId = $videoIds[$i]
    $index = $i + 1
    $timestampTag = $SeekSeconds.ToString("0.##").Replace(",", ".")
    $outputFile = Join-Path $OutputDir "${videoId}_${timestampTag}s.jpg"

    Write-Host "[$index/$($videoIds.Count)] $videoId" -ForegroundColor Gray -NoNewline

    # Vérifier si la capture existe déjà
    if ($SkipExisting -and (Test-Path $outputFile)) {
        Write-Host " -> déjà capturé, ignoré" -ForegroundColor DarkYellow
        $skipped++
        continue
    }

    # Récupérer l'URL directe du flux vidéo
    try {
        $streamUrl = & yt-dlp --get-url -f "bv*[height<=${MaxHeight}]" "https://www.youtube.com/watch?v=$videoId" 2>$null
        if ([string]::IsNullOrWhiteSpace($streamUrl)) {
            Write-Host " -> ERREUR: yt-dlp n'a retourné aucune URL" -ForegroundColor Red
            $failed++
            continue
        }
    }
    catch {
        Write-Host " -> ERREUR yt-dlp: $_" -ForegroundColor Red
        $failed++
        continue
    }

    # Extraire la frame avec ffmpeg
    try {
        $ffmpegArgs = @(
            "-ss", "$SeekSeconds",
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
            Write-Host " -> OK ($('{0:N0}' -f ($size / 1KB)) Ko)" -ForegroundColor Green
            $succeeded++
        }
        else {
            Write-Host " -> ERREUR: ffmpeg n'a pas créé le fichier" -ForegroundColor Red
            $failed++
        }
    }
    catch {
        Write-Host " -> ERREUR ffmpeg: $_" -ForegroundColor Red
        $failed++
    }

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
