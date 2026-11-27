<#
.SYNOPSIS
    Installs (or uninstalls with -Uninstall) claude-here: the command and the "Open Claude here"
    entry in the File Explorer context menu.

.DESCRIPTION
    Run it from YOUR account (not the Claude one). No administrator rights needed.

    1. Lists the local accounts and asks which one to run Claude under.
    2. Copies claude-here.ps1, filled in with that account, to the install folder, along with
       claude-here.cmd so it can also be run from cmd.exe.
    3. Copies claude-session.ps1 to C:\ProgramData\ClaudeHere, readable by the Claude account
       but not modifiable by it. That script checks, under that account, that Windows Terminal
       and Claude Code are installed.
    4. Adds the install folder to your account's PATH.
    5. Adds the context menu entry (folders, folder background, drives).
       On Windows 11, it is under "Show more options" (or Shift+right-click).

    Running the installer again updates an existing installation.

.PARAMETER Account
    Local account to run Claude under. Prompted for if omitted.

.PARAMETER InstallDir
    Folder to copy claude-here to. The Claude account must NOT be able to write to it: otherwise
    it could modify a script that you run under your own account.

.PARAMETER Uninstall
    Removes everything the installer added.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Account,
    [string] $InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\ClaudeHere'),
    [switch] $Uninstall
)

$ErrorActionPreference = 'Stop'

$Name             = 'ClaudeHere'
$InfoKey          = "HKCU:\Software\$Name"   # remembers the installation, for updates and uninstall
# Directory (click on a folder), Directory\Background (click in empty space), Drive (click on a drive)
$MenuKeys         = 'Directory', 'Directory\Background', 'Drive' |
    ForEach-Object { "HKCU:\Software\Classes\$_\shell\$Name" }
$SessionDir       = Join-Path $env:ProgramData $Name
$LauncherTemplate = Join-Path $PSScriptRoot 'claude-here.ps1'
$SessionTemplate  = Join-Path $PSScriptRoot 'claude-session.ps1'
$MySid            = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value

function Select-Account([string] $Default) {
    # Built-in accounts excluded: Administrator (500), Guest (501), DefaultAccount (503),
    # WDAGUtilityAccount (504).
    $accounts = @(Get-LocalUser |
        Where-Object { $_.Enabled -and $_.SID.Value -notmatch '-(500|501|503|504)$' -and $_.SID.Value -ne $MySid } |
        Sort-Object Name)
    if (-not $accounts) {
        throw 'No usable local account. Create a local account dedicated to Claude first.'
    }

    Write-Host 'Local accounts:'
    for ($i = 0; $i -lt $accounts.Count; $i++) {
        $description = if ($accounts[$i].Description) { "  ($($accounts[$i].Description))" } else { '' }
        Write-Host ("  {0}. {1}{2}" -f ($i + 1), $accounts[$i].Name, $description)
    }

    $defaultNumber = 0
    for ($i = 0; $i -lt $accounts.Count; $i++) {
        if ($accounts[$i].Name -eq $Default) { $defaultNumber = $i + 1 }
    }
    if (-not $defaultNumber -and $accounts.Count -eq 1) { $defaultNumber = 1 }

    while ($true) {
        $prompt = 'Number of the account to run Claude under'
        if ($defaultNumber) { $prompt += " [$defaultNumber]" }
        $answer = Read-Host $prompt
        if ([string]::IsNullOrWhiteSpace($answer) -and $defaultNumber) { $answer = "$defaultNumber" }
        $number = 0
        if ([int]::TryParse($answer, [ref] $number) -and $number -ge 1 -and $number -le $accounts.Count) {
            return $accounts[$number - 1].Name
        }
        Write-Host "Enter a number between 1 and $($accounts.Count)." -ForegroundColor Yellow
    }
}

function Test-Administrator([string] $Sid) {
    try {
        return [bool] (Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop |
            Where-Object { $_.SID.Value -eq $Sid })
    } catch {
        return $false   # group unreadable (unresolved domain members): do not block
    }
}

function Test-Windows11 {
    # ProductName still says "Windows 10" on Windows 11: only the build number is reliable.
    $build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
    return $build -ge 22000
}

function Send-EnvironmentChange {
    # Tells File Explorer the PATH changed: new consoles will pick it up.
    if (-not ('ClaudeHere.Win32' -as [type])) {
        Add-Type -Namespace ClaudeHere -Name Win32 -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam,
    string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $result = [UIntPtr]::Zero
    [ClaudeHere.Win32]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment',
        2, 5000, [ref] $result) | Out-Null
}

function Get-UserPath {
    # Raw read: keeps %VARIABLES% as they are (REG_EXPAND_SZ).
    $key = Get-Item 'HKCU:\Environment'
    return [string] $key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
}

function Set-UserPath([string[]] $Entries) {
    $value = ($Entries | Where-Object { $_ }) -join ';'
    if ($PSCmdlet.ShouldProcess('User PATH', "Write '$value'")) {
        Set-ItemProperty 'HKCU:\Environment' -Name Path -Value $value -Type ExpandString
        Send-EnvironmentChange
    }
}

function Test-SamePath([string] $A, [string] $B) {
    $A = [Environment]::ExpandEnvironmentVariables($A).TrimEnd('\')
    $B = [Environment]::ExpandEnvironmentVariables($B).TrimEnd('\')
    return [string]::Equals($A, $B, [StringComparison]::OrdinalIgnoreCase)
}

function ConvertTo-PSLiteral([string] $Value) {
    return "'" + $Value.Replace("'", "''") + "'"
}

function Write-Utf8Bom([string] $FilePath, [string] $Content) {
    # UTF-8 BOM: without it, PowerShell 5.1 reads non-ASCII characters as ANSI.
    [System.IO.File]::WriteAllText($FilePath, $Content, [System.Text.UTF8Encoding]::new($true))
}

# ---------------------------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------------------------
if ($Uninstall) {
    $info = Get-ItemProperty -LiteralPath $InfoKey -ErrorAction SilentlyContinue
    $dir = if ($info) { $info.InstallDir } else { $InstallDir }

    foreach ($key in $MenuKeys) {
        if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse }
    }
    Write-Host 'Context menu entry removed.'

    foreach ($file in 'claude-here.ps1', 'claude-here.cmd') {
        $filePath = Join-Path $dir $file
        if (Test-Path -LiteralPath $filePath) { Remove-Item -LiteralPath $filePath }
    }
    if ((Test-Path -LiteralPath $dir) -and -not (Get-ChildItem -LiteralPath $dir -Force)) {
        Remove-Item -LiteralPath $dir
    }
    if (Test-Path -LiteralPath $SessionDir) { Remove-Item -LiteralPath $SessionDir -Recurse -Force }
    Write-Host "Files removed from $dir and $SessionDir."

    $entries = (Get-UserPath) -split ';'
    if ($entries | Where-Object { Test-SamePath $_ $dir }) {
        Set-UserPath ($entries | Where-Object { -not (Test-SamePath $_ $dir) })
        Write-Host 'Folder removed from the PATH.'
    }

    if (Test-Path -LiteralPath $InfoKey) { Remove-Item -LiteralPath $InfoKey -Recurse }
    Write-Host 'claude-here is uninstalled.' -ForegroundColor Green
    return
}

# ---------------------------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------------------------
foreach ($file in $LauncherTemplate, $SessionTemplate) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "File not found: $file" }
}
$previousInstall = Get-ItemProperty -LiteralPath $InfoKey -ErrorAction SilentlyContinue

# 1. Claude account
if (-not $Account) {
    $Account = Select-Account $(if ($previousInstall) { $previousInstall.Account })
}
try {
    $sid = ([System.Security.Principal.NTAccount] $Account).Translate(
        [System.Security.Principal.SecurityIdentifier]).Value
} catch {
    throw "Account not found: $Account"
}
if ($sid -eq $MySid) {
    throw "$Account is your own account: a separate account is needed to isolate Claude."
}
if (Test-Administrator $sid) {
    Write-Host "Warning: $Account is an administrator of this machine, so Claude will not really be isolated." -ForegroundColor Yellow
}

# 2. Launcher, run under your account
$InstallDir = [System.IO.Path]::GetFullPath($InstallDir)
$userProfile = $env:USERPROFILE.TrimEnd('\') + '\'
if (-not ($InstallDir + '\').StartsWith($userProfile, [StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "Warning: $InstallDir is outside your profile. Make sure $Account cannot write to it." -ForegroundColor Yellow
}

$sessionPath = Join-Path $SessionDir 'claude-session.ps1'
$launcher = (Get-Content -LiteralPath $LauncherTemplate -Raw -Encoding UTF8).
    Replace("'__ACCOUNT__'", (ConvertTo-PSLiteral $Account)).
    Replace("'__SESSION__'", (ConvertTo-PSLiteral $sessionPath))

$launcherPath = Join-Path $InstallDir 'claude-here.ps1'
$cmdPath      = Join-Path $InstallDir 'claude-here.cmd'
$cmd = "@powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0claude-here.ps1`" %*`r`n"

if ($PSCmdlet.ShouldProcess($InstallDir, 'Copy claude-here.ps1 and claude-here.cmd')) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Utf8Bom $launcherPath $launcher
    [System.IO.File]::WriteAllText($cmdPath, $cmd, [System.Text.Encoding]::ASCII)
}
Write-Host "Launcher copied to $InstallDir."

# 3. Session script, run under the Claude account
if ($PSCmdlet.ShouldProcess($SessionDir, 'Copy claude-session.ps1')) {
    if (Test-Path -LiteralPath $SessionDir) {
        # A folder created by someone else (the Claude account, for instance) is not safe.
        $owner = (Get-Acl -LiteralPath $SessionDir).GetOwner(
            [System.Security.Principal.SecurityIdentifier]).Value
        if ($owner -ne $MySid) {
            throw "$SessionDir belongs to another account: delete it (as administrator), then run the installer again."
        }
    } else {
        New-Item -ItemType Directory -Path $SessionDir | Out-Null
    }
    # Explicit rights, no inheritance: by default, all users can create files in ProgramData
    # subfolders. Here: read-only for them.
    $output = & icacls.exe $SessionDir /inheritance:r /grant:r `
        "*${MySid}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Could not set permissions on ${SessionDir}: $output" }
    Write-Utf8Bom $sessionPath (Get-Content -LiteralPath $SessionTemplate -Raw -Encoding UTF8)
}
Write-Host "Session script copied to $SessionDir."

# 4. PATH
$entries = (Get-UserPath) -split ';' | Where-Object { $_ }
if ($entries | Where-Object { Test-SamePath $_ $InstallDir }) {
    Write-Host 'Folder already on the PATH.'
} else {
    Set-UserPath (@($entries) + $InstallDir)
    Write-Host 'Folder added to the PATH (effective in new consoles).'
}

# 5. Context menu
# "%V." rather than "%V": on a drive, %V is "C:\", and the trailing \" would break the quoting.
# claude-here.ps1 strips the dot with GetFullPath.
$label   = "Open Claude here ($($Account -replace '^.*\\', ''))"
$command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$launcherPath`" `"%V.`""
if ($PSCmdlet.ShouldProcess('HKCU:\Software\Classes', "Add the '$label' entry: $command")) {
    foreach ($key in $MenuKeys) {
        New-Item -Path $key -Force -Value $label | Out-Null
        New-ItemProperty -LiteralPath $key -Name 'Icon' -Value 'powershell.exe' -Force | Out-Null
        New-Item -Path "$key\command" -Force -Value $command | Out-Null
    }
}
Write-Host "Context menu entry '$label' added."

# Remember the installation (updates and uninstall)
if ($PSCmdlet.ShouldProcess($InfoKey, 'Save installation info')) {
    New-Item -Path $InfoKey -Force | Out-Null
    New-ItemProperty -LiteralPath $InfoKey -Name Account -Value $Account -Force | Out-Null
    New-ItemProperty -LiteralPath $InfoKey -Name InstallDir -Value $InstallDir -Force | Out-Null
}

Write-Host ''
Write-Host 'claude-here is installed.' -ForegroundColor Green
if (Test-Windows11) {
    Write-Host "  - Right-click a folder, then 'Show more options' (or Shift+right-click): 'Open Claude here'."
} else {
    Write-Host "  - Right-click a folder: 'Open Claude here'."
}
Write-Host '  - In a new console: claude-here [folder]'
Write-Host "Windows Terminal and Claude Code must be installed under the $Account account."
