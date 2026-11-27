<#
.SYNOPSIS
    Opens Windows Terminal under the account dedicated to Claude, in a given folder, and starts
    Claude Code there.

.DESCRIPTION
    This file is a TEMPLATE: installer.ps1 writes a copy of it, with the account filled in, to a
    folder on the PATH. That copy is the one actually used (the "claude-here" command and the
    context menu entry).

    Runs under YOUR account. It calls runas.exe, which asks for the Claude account's password and
    starts claude-session.ps1 under that account. claude-session.ps1 checks that Windows Terminal
    and Claude Code are installed, then starts them. The folder must be readable by that account
    (so not inside your profile).

.PARAMETER Path
    Starting folder. Defaults to the current folder.

.EXAMPLE
    claude-here C:\Claude\Pro\my-project

.EXAMPLE
    claude-here C:\Claude\Pro -WhatIf      # shows the command without running it
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [string] $Path = (Get-Location).ProviderPath
)

$ErrorActionPreference = 'Stop'

# Values filled in by installer.ps1.
$Account = '__ACCOUNT__'
$Session = '__SESSION__'   # claude-session.ps1, readable by the Claude account

function Stop-WithError([string] $Message) {
    Write-Host $Message -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}

if ($Account -eq ('__' + 'ACCOUNT__')) {
    Stop-WithError 'This file is a template. Run installer.cmd to install claude-here.'
}

# Normalized absolute path. GetFullPath also strips a trailing dot
# (the context menu passes "%V." to work around the "C:\" issue described below).
$Path = [System.IO.Path]::GetFullPath($Path)

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Stop-WithError "Folder not found: $Path"
}
# Trailing backslash added so that C:\Users\bob is not mistaken for C:\Users\bob-claude.
$userProfile = $env:USERPROFILE.TrimEnd('\') + '\'
if (($Path.TrimEnd('\') + '\').StartsWith($userProfile, [StringComparison]::OrdinalIgnoreCase)) {
    Stop-WithError "The folder is inside your profile ($env:USERPROFILE): $Account cannot access it."
}
if ($Path.Contains(';')) {
    # Windows Terminal uses ';' to separate its subcommands.
    Stop-WithError "Paths containing ';' are not supported: $Path"
}
if (-not (Test-Path -LiteralPath $Session -PathType Leaf)) {
    Stop-WithError "Script not found: $Session. Run installer.cmd again."
}

# A trailing backslash right before a quote ("C:\") is read as \" (an escaped quote).
# "C:\." refers to the same folder without that pitfall.
if ($Path.EndsWith('\')) { $Path += '.' }

# Command run by runas under the Claude account. It is passed to runas as ONE argument,
# hence the inner quotes escaped as \".
$command   = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \`"$Session\`" \`"$Path\`""
$arguments = "/user:$Account `"$command`""

if ($PSCmdlet.ShouldProcess("runas.exe $arguments", 'Run')) {
    # Start-Process passes the string as is: PowerShell 5.1 does not rewrite the quotes.
    # -NoNewWindow: the password prompt shows up in this console.
    # No -Wait: it would also wait for the processes started by runas (Windows Terminal, Claude)
    # and this console would stay open behind them. WaitForExit only waits for runas itself.
    $p = Start-Process runas.exe -ArgumentList $arguments -NoNewWindow -PassThru
    $null = $p.Handle   # keeps the handle open, otherwise ExitCode is empty after exit
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) {
        Stop-WithError "runas failed (exit code $($p.ExitCode))."
    }
}
