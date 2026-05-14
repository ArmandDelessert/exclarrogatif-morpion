<#
.SYNOPSIS
    Recadre un lot d'images à l'aide de ffmpeg.

.DESCRIPTION
    Applique un recadrage (crop) à toutes les images d'un dossier d'entrée
    et enregistre les résultats dans un dossier de sortie.

.PARAMETER InputDir
    Répertoire contenant les images à recadrer.

.PARAMETER OutputDir
    Répertoire de sortie pour les images recadrées. Créé automatiquement si inexistant.

.PARAMETER Width
    Largeur du rectangle de recadrage en pixels.

.PARAMETER Height
    Hauteur du rectangle de recadrage en pixels.

.PARAMETER X
    Position X (depuis le bord gauche) du coin supérieur gauche du rectangle (par défaut 0).

.PARAMETER Y
    Position Y (depuis le bord supérieur) du coin supérieur gauche du rectangle (par défaut 0).

.PARAMETER Filter
    Filtre glob pour sélectionner les images (par défaut "*.jpg").

.EXAMPLE
    .\Crop-Images.ps1 -InputDir frames -OutputDir frames_crop -Width 165 -Height 175 -X 0 -Y 288
#>
param (
    [Parameter(Mandatory = $true)]
    [string]$InputDir,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [Parameter(Mandatory = $true)]
    [int]$Width,

    [Parameter(Mandatory = $true)]
    [int]$Height,

    [int]$X = 0,

    [int]$Y = 0,

    [string]$Filter = "*.jpg"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Error "ffmpeg n'est pas installé ou n'est pas dans le PATH."
    exit 1
}

if (-not (Test-Path $InputDir)) {
    Write-Error "Le répertoire d'entrée '$InputDir' n'existe pas."
    exit 1
}

$images = Get-ChildItem -Path $InputDir -Filter $Filter -File | Sort-Object Name
if ($images.Count -eq 0) {
    Write-Error "Aucune image correspondant à '$Filter' trouvée dans '$InputDir'."
    exit 1
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$cropFilter = "crop=${Width}:${Height}:${X}:${Y}"

Write-Host "Recadrage de $($images.Count) image(s) avec $cropFilter" -ForegroundColor Cyan
Write-Host "Entrée  : $InputDir" -ForegroundColor Cyan
Write-Host "Sortie  : $OutputDir" -ForegroundColor Cyan
Write-Host ""

$succeeded = 0
$failed = 0

for ($i = 0; $i -lt $images.Count; $i++) {
    $image = $images[$i]
    $outputFile = Join-Path $OutputDir $image.Name
    $index = $i + 1

    Write-Host "[$index/$($images.Count)] $($image.Name)" -ForegroundColor Gray -NoNewline

    try {
        $ffmpegOutput = & ffmpeg -i $image.FullName -vf $cropFilter -update 1 -y $outputFile 2>&1
        if (Test-Path $outputFile) {
            Write-Host " -> OK" -ForegroundColor Green
            $succeeded++
        }
        else {
            Write-Host " -> ERREUR: fichier non créé" -ForegroundColor Red
            $failed++
        }
    }
    catch {
        Write-Host " -> ERREUR: $_" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "--- RÉSULTATS ---" -ForegroundColor Green
Write-Host "Réussies : $succeeded" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "Échouées : $failed" -ForegroundColor Red
}
