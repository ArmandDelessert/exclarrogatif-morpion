<#
.SYNOPSIS
    Ajoute des liens YouTube cliquables aux nœuds d'un fichier SVG généré depuis un graphe DOT.

.DESCRIPTION
    Chaque nœud du SVG contient un élément <title> avec l'identifiant de la vidéo YouTube.
    Ce script enveloppe le contenu de chaque nœud dans un élément <a> pointant vers la vidéo.

.PARAMETER InputPath
    Chemin du fichier SVG d'entrée.

.PARAMETER OutputPath
    Chemin du fichier SVG de sortie. Si omis, écrit à côté de l'entrée avec le suffixe "-links".

.EXAMPLE
    .\Add-YouTubeLinksToSvg.ps1 -InputPath graph.svg
    .\Add-YouTubeLinksToSvg.ps1 -InputPath graph.svg -OutputPath graph-clickable.svg
#>
param (
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $OutputPath) {
    $dir = [System.IO.Path]::GetDirectoryName($InputPath)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)
    $OutputPath = [System.IO.Path]::Combine($dir, "$name-links.svg")
}

$content = Get-Content -Path $InputPath -Raw -Encoding UTF8

$pattern = '(<g\s+id="node\d+"\s+class="node">\s*\n)(<title>)([^<]+)(</title>)(.*?)(</g>)'
$replacement = {
    param ($match)
    $gOpen = $match.Groups[1].Value
    $titleOpen = $match.Groups[2].Value
    $videoId = $match.Groups[3].Value
    $titleClose = $match.Groups[4].Value
    $innerContent = $match.Groups[5].Value
    $gClose = $match.Groups[6].Value

    $url = "https://www.youtube.com/watch?v=$videoId"
    return "${gOpen}<a xlink:href=`"$url`" href=`"$url`" target=`"_blank`">`n${titleOpen}${videoId}${titleClose}${innerContent}</a>`n${gClose}"
}

$result = [regex]::Replace($content, $pattern, $replacement, [System.Text.RegularExpressions.RegexOptions]::Singleline)

Set-Content -Path $OutputPath -Value $result -Encoding UTF8 -NoNewline

Write-Host "SVG avec liens généré : $OutputPath" -ForegroundColor Green
