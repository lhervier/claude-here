<#
.SYNOPSIS
    Starts Claude Code in Windows Terminal. Runs UNDER THE CLAUDE ACCOUNT (through runas).

.DESCRIPTION
    Called by claude-here.ps1. Checks that Windows Terminal and claude.exe are installed for the
    current account (otherwise reports it and stops), then opens Windows Terminal in the
    requested folder with Claude Code.

    installer.ps1 copies it to C:\ProgramData\ClaudeHere: the Claude account can read it but
    cannot modify it.

.PARAMETER Path
    Starting folder.
#>
param(
    [Parameter(Mandatory, Position = 0)]
    [string] $Path
)

$ErrorActionPreference = 'Stop'

function Stop-WithError([string] $Message) {
    Write-Host $Message -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}

# Looks in the PATH first, then in the usual locations.
function Find-Executable([string] $Command, [string[]] $Locations) {
    $found = Get-Command $Command -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($found) { return $found.Source }
    foreach ($location in $Locations) {
        if (Test-Path -LiteralPath $location -PathType Leaf) { return $location }
    }
    return $null
}

$terminalLocations = @(Join-Path $env:USERPROFILE 'Tools\WindowsTerminal\WindowsTerminal.exe')
$claudeLocations   = @(Join-Path $env:USERPROFILE '.local\bin\claude.exe')

$terminal = Find-Executable 'wt.exe' $terminalLocations
$claude   = Find-Executable 'claude.exe' $claudeLocations

$missing = @()
if (-not $terminal) {
    $missing += "  - Windows Terminal: no wt.exe on the PATH, nor $($terminalLocations -join ', ')"
}
if (-not $claude) {
    $missing += "  - Claude Code: no claude.exe on the PATH, nor $($claudeLocations -join ', ')"
}
if ($missing) {
    Stop-WithError ("Not found for account ${env:USERNAME}:`n" + ($missing -join "`n") +
        "`nInstall them under this account, then try again.")
}

$Path = [System.IO.Path]::GetFullPath($Path)
if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Stop-WithError "Folder not accessible to ${env:USERNAME}: $Path"
}

# Same pitfall as in the caller: "C:\" would make \" read as an escaped quote.
if ($Path.EndsWith('\')) { $Path += '.' }
Start-Process -FilePath $terminal -ArgumentList "-d `"$Path`" `"$claude`""
