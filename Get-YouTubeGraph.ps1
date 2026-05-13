<#
.SYNOPSIS
    Parcourt les écrans de fin des vidéos YouTube pour générer un graphe ou une liste.

.DESCRIPTION
    Récupère les éléments d'écran de fin configurés par le créateur (endscreenElementRenderer)
    en scrappant les pages YouTube. L'API InnerTube et yt-dlp n'exposent pas ces données.

.PARAMETER StartVideoId
    L'identifiant de la vidéo YouTube de départ.

.PARAMETER OnlySameChannel
    Si spécifié, ne suit que les vidéos de la même chaîne que la vidéo de départ.

.PARAMETER MaxDepth
    Profondeur maximale de parcours (illimitée par défaut).

.PARAMETER OutputFormat
    Format de sortie : List, GraphDOT ou GraphCSV.

.PARAMETER DelayMs
    Délai en millisecondes entre chaque requête HTTP (par défaut 500ms).

.EXAMPLE
    .\Get-YouTubeGraph.ps1 -StartVideoId "UnDjokbZjbs" -OutputFormat List
    .\Get-YouTubeGraph.ps1 -StartVideoId "UnDjokbZjbs" -OnlySameChannel -MaxDepth 3
#>
param (
    [Parameter(Mandatory = $true)]
    [string]$StartVideoId,

    [switch]$OnlySameChannel,

    [int]$MaxDepth = [int]::MaxValue,

    [ValidateSet("List", "GraphDOT", "GraphCSV")]
    [string]$OutputFormat = "GraphDOT",

    [int]$DelayMs = 500
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

function Get-EndScreenData {
    param ([string]$VideoId)

    $url = "https://www.youtube.com/watch?v=$VideoId"

    try {
        $response = Invoke-WebRequest -Uri $url -Headers @{ "User-Agent" = $UserAgent } -UseBasicParsing -TimeoutSec 15
        $html = $response.Content
    }
    catch {
        Write-Host "  ERREUR: Impossible de récupérer $VideoId : $_" -ForegroundColor Red
        return $null
    }

    $title = $null
    if ($html -match '<title>([^<]+)</title>') {
        $title = $Matches[1] -replace ' - YouTube$', ''
    }

    $channelId = $null
    if ($html -match '"channelId"\s*:\s*"([^"]+)"') {
        $channelId = $Matches[1]
    }

    $endScreenIds = [System.Collections.Generic.List[string]]::new()
    $pattern = '"endscreenElementRenderer"\s*:\s*\{[^}]*?"style"\s*:\s*"VIDEO".*?"watchEndpoint"\s*:\s*\{\s*"videoId"\s*:\s*"([^"]+)"'
    $regexMatches = [regex]::Matches($html, $pattern)
    foreach ($m in $regexMatches) {
        $id = $m.Groups[1].Value
        if (-not $endScreenIds.Contains($id)) {
            $endScreenIds.Add($id)
        }
    }

    return [PSCustomObject]@{
        Title        = $title
        ChannelId    = $channelId
        EndScreenIds = $endScreenIds
    }
}

$Visited = [System.Collections.Generic.Dictionary[string, string]]::new()
$Edges = [System.Collections.Generic.List[PSCustomObject]]::new()
$Queue = [System.Collections.Generic.Queue[PSCustomObject]]::new()

$Queue.Enqueue([PSCustomObject]@{ Id = $StartVideoId; Depth = 0 })
$startChannelId = $null

Write-Host "Début du parcours depuis la vidéo $StartVideoId..." -ForegroundColor Cyan

while ($Queue.Count -gt 0) {
    $current = $Queue.Dequeue()
    $videoId = $current.Id
    $depth = $current.Depth

    if ($Visited.ContainsKey($videoId) -or $depth -gt $MaxDepth) {
        continue
    }

    Write-Host "[$($Visited.Count + 1)] Profondeur $depth - Analyse de $videoId (file d'attente: $($Queue.Count))..." -ForegroundColor Gray

    $data = Get-EndScreenData -VideoId $videoId

    if ($null -eq $data) {
        $Visited[$videoId] = "(erreur)"
        continue
    }

    if ($OnlySameChannel -and $null -ne $startChannelId -and $data.ChannelId -ne $startChannelId) {
        $Visited[$videoId] = $data.Title
        Write-Host "  Ignorée (chaîne différente : $($data.ChannelId))" -ForegroundColor DarkYellow
        continue
    }

    $Visited[$videoId] = $data.Title

    if ($null -eq $startChannelId -and $null -ne $data.ChannelId) {
        $startChannelId = $data.ChannelId
        Write-Host "  Chaîne de départ : $startChannelId" -ForegroundColor Cyan
    }

    Write-Host "  Titre : $($data.Title)" -ForegroundColor White
    Write-Host "  End screens trouvés : $($data.EndScreenIds.Count)" -ForegroundColor Yellow

    foreach ($targetId in $data.EndScreenIds) {
        $Edges.Add([PSCustomObject]@{ From = $videoId; To = $targetId })

        if (-not $Visited.ContainsKey($targetId)) {
            $Queue.Enqueue([PSCustomObject]@{ Id = $targetId; Depth = ($depth + 1) })
        }
    }

    if ($Queue.Count -gt 0 -and $DelayMs -gt 0) {
        Start-Sleep -Milliseconds $DelayMs
    }
}

Write-Host "`n--- RÉSULTATS ---" -ForegroundColor Green
Write-Host "Vidéos visitées : $($Visited.Count)" -ForegroundColor Green
Write-Host "Liens (arêtes)  : $($Edges.Count)" -ForegroundColor Green
Write-Host ""

switch ($OutputFormat) {
    "List" {
        foreach ($entry in $Visited.GetEnumerator()) {
            Write-Output "$($entry.Key)`t$($entry.Value)"
        }
    }
    "GraphDOT" {
        Write-Output "digraph YouTubeEndScreens {"
        Write-Output "    rankdir=LR;"
        foreach ($entry in $Visited.GetEnumerator()) {
            $label = ($entry.Value -replace '"', '\"')
            $url = "https://www.youtube.com/watch?v=$($entry.Key)"
            Write-Output "    `"$($entry.Key)`" [label=`"$label`" URL=`"$url`" target=`"_blank`"];"
        }
        foreach ($edge in $Edges) {
            Write-Output "    `"$($edge.From)`" -> `"$($edge.To)`";"
        }
        Write-Output "}"
    }
    "GraphCSV" {
        Write-Output "Source,Target"
        foreach ($edge in $Edges) {
            Write-Output "$($edge.From),$($edge.To)"
        }
    }
}
