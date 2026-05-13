<#
.SYNOPSIS
    Parcourt les écrans de fin des vidéos YouTube pour générer un graphe ou une liste.
#>
param (
    [Parameter(Mandatory = $true)]
    [string]$StartVideoId,

    [Parameter(Mandatory = $false)]
    [switch]$OnlySameChannel,

    [Parameter(Mandatory = $false)]
    [int]$MaxDepth = [int]::MaxValue,

    [Parameter(Mandatory = $false)]
    [ValidateSet("List", "GraphDOT", "GraphCSV")]
    [string]$OutputFormat = "GraphDOT"
)

$Visited = @{}
$Edges = @()
$Queue = New-Object System.Collections.Generic.Queue[PSObject]

# Initialisation
$Queue.Enqueue(@{ Id = $StartVideoId; Depth = 0 })

Write-Host "Début du parcours. Appuyez sur 'q' pour arrêter prématurément." -ForegroundColor Cyan

while ($Queue.Count -gt 0) {
    $Current = $Queue.Dequeue()
    $vId = $Current.Id
    $depth = $Current.Depth

    # Éviter les boucles et respecter la profondeur
    if ($Visited.ContainsKey($vId) -or $depth -gt $MaxDepth) {
        continue
    }

    Write-Host "Analyse de la vidéo : $vId (Profondeur: $depth)..." -ForegroundColor Gray
    
    # Récupération des métadonnées via yt-dlp
    $jsonRaw = & yt-dlp --dump-json --no-download "https://www.youtube.com/watch?v=$vId" 2>$null
    if ($null -eq $jsonRaw) { continue }
    
    $data = $jsonRaw | ConvertFrom-Json
    $originalChannelId = $data.channel_id
    
    # Marquer comme visité
    $Visited[$vId] = $data.title

    # Extraction des écrans de fin (end_screens)
    if ($null -ne $data.end_screens) {
        foreach ($screen in $data.end_screens) {
            # On ne suit que les éléments de type vidéo ayant un ID
            if ($screen.type -eq "video" -and $null -ne $screen.id) {
                $targetId = $screen.id
                
                # Vérification de la chaîne si l'option est activée
                $shouldFollow = $true
                if ($OnlySameChannel) {
                    # Note : Nécessite un appel rapide pour vérifier le channel_id de la cible
                    # Pour optimiser, on peut aussi comparer le channel_url si disponible
                    if ($null -ne $screen.channel_id -and $screen.channel_id -ne $originalChannelId) {
                        $shouldFollow = $false
                    }
                }

                # Stockage du lien (arête)
                $Edges += [PSCustomObject]@{ From = $vId; To = $targetId }

                if ($shouldFollow -and -not $Visited.ContainsKey($targetId)) {
                    $Queue.Enqueue(@{ Id = $targetId; Depth = ($depth + 1) })
                }
            }
        }
    }
}

# Génération de la sortie
Write-Host "`n--- RÉSULTATS ---" -ForegroundColor Green

switch ($OutputFormat) {
    "List" {
        $Visited.Keys | ForEach-Object { $_ }
    }
    "GraphDOT" {
        "digraph YouTubeTraversal {"
        $Edges | ForEach-Object { "    `"$($_.From)`" -> `"$($_.To)`";" }
        "}"
    }
    "GraphCSV" {
        "Source,Target"
        $Edges | ForEach-Object { "$($_.From),$($_.To)" }
    }
}