<#
.SYNOPSIS
    Ouvre Windows Terminal sous le compte dédié à Claude, dans un dossier donné, et y lance Claude Code.

.DESCRIPTION
    Ce fichier est un MODÈLE : installer.ps1 en fait une copie, avec le compte et les chemins
    renseignés, dans un dossier du PATH. C'est cette copie qui est utilisée (commande
    « claude-ici » et menu contextuel).

    S'exécute sous TON compte. Il appelle runas.exe, qui demande le mot de passe du compte Claude
    et lance claude-session.ps1 sous ce compte. C'est lui qui vérifie que Windows Terminal et
    Claude Code sont installés, puis les lance. Le dossier doit être lisible par ce compte
    (donc pas dans ton profil).

.PARAMETER Dossier
    Dossier de démarrage. Par défaut : le dossier courant.

.EXAMPLE
    claude-ici C:\Claude\Pro\developpeur-augmente

.EXAMPLE
    claude-ici C:\Claude\Pro -WhatIf      # affiche la commande sans la lancer
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [string] $Dossier = (Get-Location).ProviderPath
)

$ErrorActionPreference = 'Stop'

# Valeurs renseignées par installer.ps1.
$Compte  = '__COMPTE__'
$Session = '__SESSION__'   # claude-session.ps1, lisible par le compte Claude

function Stop-AvecErreur([string] $Message) {
    Write-Host $Message -ForegroundColor Red
    Read-Host 'Entrée pour fermer'
    exit 1
}

if ($Compte -eq ('__' + 'COMPTE__')) {
    Stop-AvecErreur 'Ce fichier est un modèle. Lance installer.cmd pour installer claude-ici.'
}

# Chemin absolu normalisé. GetFullPath supprime aussi un éventuel point final
# (le menu contextuel passe "%V." pour contourner le problème de "C:\" décrit ci-dessous).
$Dossier = [System.IO.Path]::GetFullPath($Dossier)

if (-not (Test-Path -LiteralPath $Dossier -PathType Container)) {
    Stop-AvecErreur "Dossier introuvable : $Dossier"
}
# Antislash ajouté pour que C:\Users\toto ne soit pas confondu avec C:\Users\toto-claude.
$profil = $env:USERPROFILE.TrimEnd('\') + '\'
if (($Dossier.TrimEnd('\') + '\').StartsWith($profil, [StringComparison]::OrdinalIgnoreCase)) {
    Stop-AvecErreur "Le dossier est dans ton profil ($env:USERPROFILE) : $Compte ne peut pas y accéder."
}
if ($Dossier.Contains(';')) {
    # Windows Terminal utilise ';' pour séparer ses sous-commandes.
    Stop-AvecErreur "Chemin contenant ';' non supporté : $Dossier"
}
if (-not (Test-Path -LiteralPath $Session -PathType Leaf)) {
    Stop-AvecErreur "Script introuvable : $Session. Relance installer.cmd."
}

# Un antislash final juste avant un guillemet ("C:\") est lu comme \" (guillemet échappé).
# "C:\." désigne le même dossier sans ce piège.
if ($Dossier.EndsWith('\')) { $Dossier += '.' }

# Commande lancée par runas sous le compte Claude. Elle est passée à runas comme UN SEUL
# argument, d'où les guillemets intérieurs échappés en \".
$commande  = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \`"$Session\`" \`"$Dossier\`""
$arguments = "/user:$Compte `"$commande`""

if ($PSCmdlet.ShouldProcess("runas.exe $arguments", 'Lancer')) {
    # Start-Process transmet la chaîne telle quelle : PowerShell 5.1 ne réécrit pas les guillemets.
    # -NoNewWindow : la demande de mot de passe s'affiche dans cette console.
    # Pas de -Wait : il attendrait aussi les processus lancés par runas (Windows Terminal, Claude)
    # et cette console resterait ouverte derrière. WaitForExit n'attend que runas lui-même.
    $p = Start-Process runas.exe -ArgumentList $arguments -NoNewWindow -PassThru
    $null = $p.Handle   # garde le handle ouvert, sinon ExitCode reste vide après la sortie
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) {
        Stop-AvecErreur "runas a échoué (code $($p.ExitCode))."
    }
}
