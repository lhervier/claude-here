<#
.SYNOPSIS
    Installe (ou désinstalle avec -Desinstaller) claude-ici : la commande et l'entrée
    « Ouvrir Claude ici » du menu contextuel de l'Explorateur.

.DESCRIPTION
    À lancer depuis TON compte (pas celui de Claude). Pas besoin d'être administrateur.

    1. Liste les comptes locaux et demande celui sous lequel lancer Claude.
    2. Copie claude-ici.ps1, renseigné avec ce compte, dans le dossier d'installation, avec
       claude-ici.cmd pour pouvoir le lancer depuis cmd.exe.
    3. Copie claude-session.ps1 dans C:\ProgramData\ClaudeIci, lisible par le compte Claude
       mais pas modifiable par lui. C'est lui qui vérifie, sous ce compte, que Windows Terminal
       et Claude Code sont installés.
    4. Ajoute le dossier d'installation au PATH de ton compte.
    5. Ajoute l'entrée au menu contextuel (dossiers, fond de dossier, lecteurs).
       Sous Windows 11, elle est dans « Afficher plus d'options » (ou Maj+clic droit).

    Relancer l'installeur met à jour une installation existante.

.PARAMETER Compte
    Compte local sous lequel lancer Claude. Demandé s'il est absent.

.PARAMETER DossierInstallation
    Dossier où copier claude-ici. Le compte Claude ne doit PAS pouvoir y écrire : sinon il
    pourrait modifier un script que tu lances sous ton compte.

.PARAMETER Desinstaller
    Retire tout ce que l'installeur a ajouté.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Compte,
    [string] $DossierInstallation = (Join-Path $env:LOCALAPPDATA 'Programs\ClaudeIci'),
    [switch] $Desinstaller
)

$ErrorActionPreference = 'Stop'

$Nom           = 'ClaudeIci'
$CleInfos      = "HKCU:\Software\$Nom"   # mémorise l'installation pour la désinstallation
# Dossier (clic sur un dossier), Directory\Background (clic dans le vide), Drive (clic sur un lecteur)
$ClesMenu      = 'Directory', 'Directory\Background', 'Drive' |
    ForEach-Object { "HKCU:\Software\Classes\$_\shell\$Nom" }
$DossierSession = Join-Path $env:ProgramData $Nom
$Modele        = Join-Path $PSScriptRoot 'claude-ici.ps1'
$ModeleSession = Join-Path $PSScriptRoot 'claude-session.ps1'
$MonSid        = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value

function Select-Compte([string] $Defaut) {
    # Comptes intégrés exclus : Administrateur (500), Invité (501), DefaultAccount (503),
    # WDAGUtilityAccount (504).
    $comptes = @(Get-LocalUser |
        Where-Object { $_.Enabled -and $_.SID.Value -notmatch '-(500|501|503|504)$' -and $_.SID.Value -ne $MonSid } |
        Sort-Object Name)
    if (-not $comptes) {
        throw 'Aucun compte local utilisable. Crée d''abord un compte local dédié à Claude.'
    }

    Write-Host 'Comptes locaux :'
    for ($i = 0; $i -lt $comptes.Count; $i++) {
        $description = if ($comptes[$i].Description) { "  ($($comptes[$i].Description))" } else { '' }
        Write-Host ("  {0}. {1}{2}" -f ($i + 1), $comptes[$i].Name, $description)
    }

    $numeroDefaut = 0
    for ($i = 0; $i -lt $comptes.Count; $i++) {
        if ($comptes[$i].Name -eq $Defaut) { $numeroDefaut = $i + 1 }
    }
    if (-not $numeroDefaut -and $comptes.Count -eq 1) { $numeroDefaut = 1 }

    while ($true) {
        $invite = 'Numéro du compte sous lequel lancer Claude'
        if ($numeroDefaut) { $invite += " [$numeroDefaut]" }
        $reponse = Read-Host $invite
        if ([string]::IsNullOrWhiteSpace($reponse) -and $numeroDefaut) { $reponse = "$numeroDefaut" }
        $numero = 0
        if ([int]::TryParse($reponse, [ref] $numero) -and $numero -ge 1 -and $numero -le $comptes.Count) {
            return $comptes[$numero - 1].Name
        }
        Write-Host "Réponds par un numéro entre 1 et $($comptes.Count)." -ForegroundColor Yellow
    }
}

function Test-Administrateur([string] $Sid) {
    try {
        return [bool] (Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop |
            Where-Object { $_.SID.Value -eq $Sid })
    } catch {
        return $false   # groupe illisible (membres de domaine non résolus) : on ne bloque pas
    }
}

function Test-Windows11 {
    # ProductName vaut encore « Windows 10 » sous Windows 11 : seul le numéro de build est fiable.
    $build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
    return $build -ge 22000
}

function Send-ChangementEnvironnement {
    # Prévient l'Explorateur que le PATH a changé : les nouvelles consoles le verront.
    if (-not ('ClaudeIci.Win32' -as [type])) {
        Add-Type -Namespace ClaudeIci -Name Win32 -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam,
    string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $resultat = [UIntPtr]::Zero
    [ClaudeIci.Win32]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment',
        2, 5000, [ref] $resultat) | Out-Null
}

function Get-PathUtilisateur {
    # Lecture brute : garde les %VARIABLES% telles quelles (REG_EXPAND_SZ).
    $cle = Get-Item 'HKCU:\Environment'
    return [string] $cle.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
}

function Set-PathUtilisateur([string[]] $Entrees) {
    $valeur = ($Entrees | Where-Object { $_ }) -join ';'
    if ($PSCmdlet.ShouldProcess('PATH utilisateur', "Écrire « $valeur »")) {
        Set-ItemProperty 'HKCU:\Environment' -Name Path -Value $valeur -Type ExpandString
        Send-ChangementEnvironnement
    }
}

function Test-MemeChemin([string] $A, [string] $B) {
    $A = [Environment]::ExpandEnvironmentVariables($A).TrimEnd('\')
    $B = [Environment]::ExpandEnvironmentVariables($B).TrimEnd('\')
    return [string]::Equals($A, $B, [StringComparison]::OrdinalIgnoreCase)
}

function ConvertTo-LitteralPS([string] $Valeur) {
    return "'" + $Valeur.Replace("'", "''") + "'"
}

function Write-Utf8Bom([string] $Chemin, [string] $Contenu) {
    # BOM UTF-8 : sans lui, PowerShell 5.1 lit le script en ANSI et casse les accents.
    [System.IO.File]::WriteAllText($Chemin, $Contenu, [System.Text.UTF8Encoding]::new($true))
}

# ---------------------------------------------------------------------------------------------
# Désinstallation
# ---------------------------------------------------------------------------------------------
if ($Desinstaller) {
    $infos = Get-ItemProperty -LiteralPath $CleInfos -ErrorAction SilentlyContinue
    $dossier = if ($infos) { $infos.DossierInstallation } else { $DossierInstallation }

    foreach ($cle in $ClesMenu) {
        if (Test-Path -LiteralPath $cle) { Remove-Item -LiteralPath $cle -Recurse }
    }
    Write-Host 'Entrée retirée du menu contextuel.'

    foreach ($fichier in 'claude-ici.ps1', 'claude-ici.cmd') {
        $chemin = Join-Path $dossier $fichier
        if (Test-Path -LiteralPath $chemin) { Remove-Item -LiteralPath $chemin }
    }
    if ((Test-Path -LiteralPath $dossier) -and -not (Get-ChildItem -LiteralPath $dossier -Force)) {
        Remove-Item -LiteralPath $dossier
    }
    if (Test-Path -LiteralPath $DossierSession) { Remove-Item -LiteralPath $DossierSession -Recurse -Force }
    Write-Host "Fichiers retirés de $dossier et $DossierSession."

    $entrees = (Get-PathUtilisateur) -split ';'
    if ($entrees | Where-Object { Test-MemeChemin $_ $dossier }) {
        Set-PathUtilisateur ($entrees | Where-Object { -not (Test-MemeChemin $_ $dossier) })
        Write-Host 'Dossier retiré du PATH.'
    }

    if (Test-Path -LiteralPath $CleInfos) { Remove-Item -LiteralPath $CleInfos -Recurse }
    Write-Host 'claude-ici est désinstallé.' -ForegroundColor Green
    return
}

# ---------------------------------------------------------------------------------------------
# Installation
# ---------------------------------------------------------------------------------------------
foreach ($fichier in $Modele, $ModeleSession) {
    if (-not (Test-Path -LiteralPath $fichier -PathType Leaf)) { throw "Fichier introuvable : $fichier" }
}
$installationPrecedente = Get-ItemProperty -LiteralPath $CleInfos -ErrorAction SilentlyContinue

# 1. Compte Claude
if (-not $Compte) {
    $Compte = Select-Compte $(if ($installationPrecedente) { $installationPrecedente.Compte })
}
try {
    $sid = ([System.Security.Principal.NTAccount] $Compte).Translate(
        [System.Security.Principal.SecurityIdentifier]).Value
} catch {
    throw "Compte introuvable : $Compte"
}
if ($sid -eq $MonSid) {
    throw "$Compte est ton propre compte : il faut un compte distinct pour isoler Claude."
}
if (Test-Administrateur $sid) {
    Write-Host "Attention : $Compte est administrateur de la machine, Claude ne sera pas vraiment isolé." -ForegroundColor Yellow
}

# 2. Lanceur, sous ton compte
$DossierInstallation = [System.IO.Path]::GetFullPath($DossierInstallation)
$profil = $env:USERPROFILE.TrimEnd('\') + '\'
if (-not ($DossierInstallation + '\').StartsWith($profil, [StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "Attention : $DossierInstallation est hors de ton profil. Vérifie que $Compte ne peut pas y écrire." -ForegroundColor Yellow
}

$cheminSession = Join-Path $DossierSession 'claude-session.ps1'
$script = (Get-Content -LiteralPath $Modele -Raw -Encoding UTF8).
    Replace("'__COMPTE__'", (ConvertTo-LitteralPS $Compte)).
    Replace("'__SESSION__'", (ConvertTo-LitteralPS $cheminSession))

$cheminScript = Join-Path $DossierInstallation 'claude-ici.ps1'
$cheminCmd    = Join-Path $DossierInstallation 'claude-ici.cmd'
$cmd = "@powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0claude-ici.ps1`" %*`r`n"

if ($PSCmdlet.ShouldProcess($DossierInstallation, 'Copier claude-ici.ps1 et claude-ici.cmd')) {
    New-Item -ItemType Directory -Path $DossierInstallation -Force | Out-Null
    Write-Utf8Bom $cheminScript $script
    [System.IO.File]::WriteAllText($cheminCmd, $cmd, [System.Text.Encoding]::ASCII)
}
Write-Host "Lanceur copié dans $DossierInstallation."

# 3. Script de session, sous le compte Claude
if ($PSCmdlet.ShouldProcess($DossierSession, 'Copier claude-session.ps1')) {
    if (Test-Path -LiteralPath $DossierSession) {
        # Un dossier créé par quelqu'un d'autre (le compte Claude, par exemple) n'est pas sûr.
        $proprietaire = (Get-Acl -LiteralPath $DossierSession).GetOwner(
            [System.Security.Principal.SecurityIdentifier]).Value
        if ($proprietaire -ne $MonSid) {
            throw "$DossierSession appartient à un autre compte : supprime-le (en administrateur) puis relance."
        }
    } else {
        New-Item -ItemType Directory -Path $DossierSession | Out-Null
    }
    # Droits explicites, sans héritage : par défaut, tous les utilisateurs peuvent créer des
    # fichiers dans les sous-dossiers de ProgramData. Ici : lecture seule pour eux.
    $sortie = & icacls.exe $DossierSession /inheritance:r /grant:r `
        "*${MonSid}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Impossible de fixer les droits de $DossierSession : $sortie" }
    Write-Utf8Bom $cheminSession (Get-Content -LiteralPath $ModeleSession -Raw -Encoding UTF8)
}
Write-Host "Script de session copié dans $DossierSession."

# 4. PATH
$entrees = (Get-PathUtilisateur) -split ';' | Where-Object { $_ }
if ($entrees | Where-Object { Test-MemeChemin $_ $DossierInstallation }) {
    Write-Host 'Dossier déjà dans le PATH.'
} else {
    Set-PathUtilisateur (@($entrees) + $DossierInstallation)
    Write-Host 'Dossier ajouté au PATH (pris en compte dans les nouvelles consoles).'
}

# 5. Menu contextuel
# "%V." et non "%V" : sur un lecteur, %V vaut "C:\", et le \" final casserait les guillemets.
# claude-ici.ps1 retire le point avec GetFullPath.
$Libelle  = "Ouvrir Claude ici ($($Compte -replace '^.*\\', ''))"
$Commande = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$cheminScript`" `"%V.`""
if ($PSCmdlet.ShouldProcess('HKCU:\Software\Classes', "Ajouter l'entrée « $Libelle » : $Commande")) {
    foreach ($cle in $ClesMenu) {
        New-Item -Path $cle -Force -Value $Libelle | Out-Null
        New-ItemProperty -LiteralPath $cle -Name 'Icon' -Value 'powershell.exe' -Force | Out-Null
        New-Item -Path "$cle\command" -Force -Value $Commande | Out-Null
    }
}
Write-Host "Entrée « $Libelle » ajoutée au menu contextuel."

# Mémorise l'installation (mise à jour et désinstallation)
if ($PSCmdlet.ShouldProcess($CleInfos, "Mémoriser l'installation")) {
    New-Item -Path $CleInfos -Force | Out-Null
    New-ItemProperty -LiteralPath $CleInfos -Name Compte -Value $Compte -Force | Out-Null
    New-ItemProperty -LiteralPath $CleInfos -Name DossierInstallation -Value $DossierInstallation -Force | Out-Null
}

Write-Host ''
Write-Host 'claude-ici est installé.' -ForegroundColor Green
if (Test-Windows11) {
    Write-Host '  - Clic droit sur un dossier, puis « Afficher plus d''options » (ou Maj+clic droit) : « Ouvrir Claude ici ».'
} else {
    Write-Host '  - Clic droit sur un dossier : « Ouvrir Claude ici ».'
}
Write-Host '  - Dans une nouvelle console : claude-ici [dossier]'
Write-Host "Windows Terminal et Claude Code doivent être installés dans le compte $Compte."
