<#
.SYNOPSIS
    Lance Claude Code dans Windows Terminal. S'exécute SOUS LE COMPTE CLAUDE (via runas).

.DESCRIPTION
    Appelé par claude-ici.ps1. Vérifie que Windows Terminal et claude.exe sont installés dans le
    compte courant (sinon, l'indique et s'arrête), puis ouvre Windows Terminal dans le dossier
    demandé avec Claude Code.

    installer.ps1 le copie dans C:\ProgramData\ClaudeIci : le compte Claude peut le lire,
    mais pas le modifier.

.PARAMETER Dossier
    Dossier de démarrage.
#>
param(
    [Parameter(Mandatory, Position = 0)]
    [string] $Dossier
)

$ErrorActionPreference = 'Stop'

function Stop-AvecErreur([string] $Message) {
    Write-Host $Message -ForegroundColor Red
    Read-Host 'Entrée pour fermer'
    exit 1
}

# Cherche d'abord dans le PATH, puis aux emplacements habituels.
function Find-Executable([string] $Commande, [string[]] $Chemins) {
    $trouve = Get-Command $Commande -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($trouve) { return $trouve.Source }
    foreach ($chemin in $Chemins) {
        if (Test-Path -LiteralPath $chemin -PathType Leaf) { return $chemin }
    }
    return $null
}

$cheminsTerminal = @(Join-Path $env:USERPROFILE 'Tools\WindowsTerminal\WindowsTerminal.exe')
$cheminsClaude   = @(Join-Path $env:USERPROFILE '.local\bin\claude.exe')

$terminal = Find-Executable 'wt.exe' $cheminsTerminal
$claude   = Find-Executable 'claude.exe' $cheminsClaude

$manquants = @()
if (-not $terminal) {
    $manquants += "  - Windows Terminal : ni wt.exe dans le PATH, ni $($cheminsTerminal -join ', ')"
}
if (-not $claude) {
    $manquants += "  - Claude Code : ni claude.exe dans le PATH, ni $($cheminsClaude -join ', ')"
}
if ($manquants) {
    Stop-AvecErreur ("Introuvable(s) pour le compte $env:USERNAME :`n" + ($manquants -join "`n") +
        "`nInstalle-les sous ce compte, puis relance.")
}

$Dossier = [System.IO.Path]::GetFullPath($Dossier)
if (-not (Test-Path -LiteralPath $Dossier -PathType Container)) {
    Stop-AvecErreur "Dossier inaccessible pour $env:USERNAME : $Dossier"
}

# Même piège qu'à l'appel : "C:\" ferait lire \" comme un guillemet échappé.
if ($Dossier.EndsWith('\')) { $Dossier += '.' }
Start-Process -FilePath $terminal -ArgumentList "-d `"$Dossier`" `"$claude`""
