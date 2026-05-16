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
    List produit un fichier TSV avec les colonnes :
    video_id, title, duration (secondes), upload_date, channel, unlisted.

.PARAMETER DelayMs
    Délai en millisecondes entre chaque requête HTTP (par défaut 500ms).

.PARAMETER ExcludeFile
    Chemin vers un fichier texte contenant des identifiants de vidéo à ignorer (un par ligne).
    Les lignes vides et les lignes commençant par # sont ignorées.
    Le format TSV (ID<tab>titre) est supporté : seul le premier champ est utilisé.

.PARAMETER CookiesFile
    Chemin vers un fichier cookies au format Netscape pour authentifier les requêtes YouTube.
    Nécessaire lorsque YouTube bloque les requêtes non authentifiées (détection anti-bot).
    Peut être généré avec l'extension "Get cookies.txt LOCALLY" ou via yt-dlp.

.EXAMPLE
    .\Get-YouTubeGraph.ps1 -StartVideoId "UnDjokbZjbs" -OutputFormat List
    .\Get-YouTubeGraph.ps1 -StartVideoId "UnDjokbZjbs" -OnlySameChannel -MaxDepth 3
    .\Get-YouTubeGraph.ps1 -StartVideoId "UnDjokbZjbs" -ExcludeFile already-visited.txt
    .\Get-YouTubeGraph.ps1 -StartVideoId "UnDjokbZjbs" -CookiesFile cookies.txt
#>
param (
    [Parameter(Mandatory = $true)]
    [string]$StartVideoId,

    [switch]$OnlySameChannel,

    [int]$MaxDepth = [int]::MaxValue,

    [ValidateSet("List", "GraphDOT", "GraphCSV")]
    [string]$OutputFormat = "GraphDOT",

    [int]$DelayMs = 500,

    [string]$ExcludeFile,

    [string]$CookiesFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Chargement des IDs à exclure
$ExcludeSet = [System.Collections.Generic.HashSet[string]]::new()
if ($ExcludeFile -and (Test-Path $ExcludeFile)) {
    foreach ($line in (Get-Content -Path $ExcludeFile -Encoding UTF8)) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "" -or $trimmed.StartsWith("#")) {
            continue
        }
        $id = ($trimmed -split "`t")[0].Trim()
        if ($id -ne "") {
            [void]$ExcludeSet.Add($id)
        }
    }
    Write-Host "$($ExcludeSet.Count) vidéo(s) à exclure chargée(s) depuis $ExcludeFile" -ForegroundColor DarkYellow
}

$UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

# Chargement des cookies depuis un fichier Netscape
$CookieHeader = $null
if ($CookiesFile) {
    if (-not (Test-Path $CookiesFile)) {
        Write-Error "Le fichier cookies '$CookiesFile' n'existe pas."
        exit 1
    }
    $cookiePairs = [System.Collections.Generic.List[string]]::new()
    foreach ($line in (Get-Content -Path $CookiesFile -Encoding UTF8)) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "" -or $trimmed.StartsWith("#")) {
            continue
        }
        $fields = $trimmed -split "`t"
        if ($fields.Count -ge 7 -and $fields[0] -match '\.youtube\.com') {
            $cookiePairs.Add("$($fields[5])=$($fields[6])")
        }
    }
    if ($cookiePairs.Count -gt 0) {
        $CookieHeader = $cookiePairs -join "; "
        Write-Host "$($cookiePairs.Count) cookie(s) YouTube chargé(s) depuis $CookiesFile" -ForegroundColor DarkYellow
    }
}

function Get-EndScreenData {
    param ([string]$VideoId)

    $url = "https://www.youtube.com/watch?v=$VideoId"
    $headers = @{ "User-Agent" = $UserAgent }
    if ($null -ne $CookieHeader) {
        $headers["Cookie"] = $CookieHeader
    }

    try {
        $response = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec 15
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

    $channelName = $null
    if ($html -match '"ownerChannelName"\s*:\s*"([^"]+)"') {
        $channelName = $Matches[1]
    }

    $duration = $null
    if ($html -match '"lengthSeconds"\s*:\s*"(\d+)"') {
        $duration = [int]$Matches[1]
    }

    $publishDate = $null
    if ($html -match '"publishDate"\s*:\s*"([^"]+)"') {
        $publishDate = $Matches[1]
    }

    $unlisted = $null
    if ($html -match '"isUnlisted"\s*:\s*(true|false)') {
        $unlisted = $Matches[1] -eq "true"
    }

    $linkedVideoIds = [System.Collections.Generic.List[string]]::new()

    # Source 1 : End screens (éléments configurés par le créateur en fin de vidéo)
    $endScreenPattern = '"endscreenElementRenderer"\s*:\s*\{[^}]*?"style"\s*:\s*"VIDEO".*?"watchEndpoint"\s*:\s*\{\s*"videoId"\s*:\s*"([^"]+)"'
    foreach ($m in [regex]::Matches($html, $endScreenPattern)) {
        $id = $m.Groups[1].Value
        if (-not $linkedVideoIds.Contains($id)) {
            $linkedVideoIds.Add($id)
        }
    }

    # Source 2 : Vidéos intégrées dans la description (structuredDescriptionVideoLockupRenderer)
    $descPattern = '"structuredDescriptionVideoLockupRenderer"\s*:\s*\{.*?"watchEndpoint"\s*:\s*\{\s*"videoId"\s*:\s*"([^"]+)"'
    foreach ($m in [regex]::Matches($html, $descPattern)) {
        $id = $m.Groups[1].Value
        if (-not $linkedVideoIds.Contains($id)) {
            $linkedVideoIds.Add($id)
        }
    }

    return [PSCustomObject]@{
        Title          = $title
        ChannelId      = $channelId
        ChannelName    = $channelName
        Duration       = $duration
        PublishDate    = $publishDate
        Unlisted       = $unlisted
        LinkedVideoIds = $linkedVideoIds
    }
}

$Visited = [System.Collections.Generic.Dictionary[string, PSCustomObject]]::new()
$Edges = [System.Collections.Generic.List[PSCustomObject]]::new()
$Queue = [System.Collections.Generic.Queue[PSCustomObject]]::new()

$Queue.Enqueue([PSCustomObject]@{ Id = $StartVideoId; Depth = 0 })
$startChannelId = $null

Write-Host "Début du parcours depuis la vidéo $StartVideoId..." -ForegroundColor Cyan

while ($Queue.Count -gt 0) {
    $current = $Queue.Dequeue()
    $videoId = $current.Id
    $depth = $current.Depth

    if ($Visited.ContainsKey($videoId) -or $depth -gt $MaxDepth -or $ExcludeSet.Contains($videoId)) {
        continue
    }

    Write-Host "[$($Visited.Count + 1)] Profondeur $depth - Analyse de $videoId (file d'attente: $($Queue.Count))..." -ForegroundColor Gray

    $data = Get-EndScreenData -VideoId $videoId

    if ($null -eq $data) {
        $Visited[$videoId] = [PSCustomObject]@{ Title = "(erreur)"; ChannelName = $null; Duration = $null; PublishDate = $null; Unlisted = $null }
        continue
    }

    if ($OnlySameChannel -and $null -ne $startChannelId -and $data.ChannelId -ne $startChannelId) {
        $Visited[$videoId] = [PSCustomObject]@{ Title = $data.Title; ChannelName = $data.ChannelName; Duration = $data.Duration; PublishDate = $data.PublishDate; Unlisted = $data.Unlisted }
        Write-Host "  Ignorée (chaîne différente : $($data.ChannelId))" -ForegroundColor DarkYellow
        continue
    }

    $Visited[$videoId] = [PSCustomObject]@{ Title = $data.Title; ChannelName = $data.ChannelName; Duration = $data.Duration; PublishDate = $data.PublishDate; Unlisted = $data.Unlisted }

    if ($null -eq $startChannelId -and $null -ne $data.ChannelId) {
        $startChannelId = $data.ChannelId
        Write-Host "  Chaîne de départ : $startChannelId" -ForegroundColor Cyan
    }

    Write-Host "  Titre : $($data.Title)" -ForegroundColor White
    Write-Host "  Vidéos liées trouvées : $($data.LinkedVideoIds.Count)" -ForegroundColor Yellow

    foreach ($targetId in $data.LinkedVideoIds) {
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
        Write-Output "video_id`ttitle`tduration`tupload_date`tchannel`tunlisted"
        foreach ($entry in $Visited.GetEnumerator()) {
            $v = $entry.Value
            $dur = if ($null -ne $v.Duration) { $v.Duration } else { "" }
            $pub = if ($null -ne $v.PublishDate) { $v.PublishDate } else { "" }
            $ch = if ($null -ne $v.ChannelName) { $v.ChannelName } else { "" }
            $unl = if ($null -ne $v.Unlisted) { $v.Unlisted.ToString().ToLower() } else { "" }
            Write-Output "$($entry.Key)`t$($v.Title)`t$dur`t$pub`t$ch`t$unl"
        }
    }
    "GraphDOT" {
        Write-Output "digraph YouTubeEndScreens {"
        Write-Output "    rankdir=LR;"
        foreach ($entry in $Visited.GetEnumerator()) {
            $title = ($entry.Value.Title -replace '"', '\"')
            $url = "https://www.youtube.com/watch?v=$($entry.Key)"
            Write-Output "    `"$($entry.Key)`" [label=`"$title\n$($entry.Key)`" URL=`"$url`" target=`"_blank`"];"
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
