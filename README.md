# claude-here

Runs Claude Code under a dedicated Windows account, isolated from yours, in the folder of your
choice: from a right-click in File Explorer ("Open Claude here") or with the `claude-here` command.

## Why

Claude Code can read files and run commands with the rights of the account it runs under. Running
it under a separate, non-administrator local account keeps it away from your profile, your
documents and your credentials: it only sees the folders you explicitly share with that account.

`claude-here` removes the friction of doing this by hand: one right-click, one password prompt,
and Claude Code opens in Windows Terminal, in the right folder, under the right account.

## How it works

```
your account                              Claude account
------------                              --------------
Explorer / claude-here
  -> claude-here.ps1  -- runas -->  claude-session.ps1
     (checks the folder)               (checks Windows Terminal and Claude Code)
                                        -> Windows Terminal -> claude.exe
```

- `claude-here.ps1` runs under **your** account. It lives in your profile, where the Claude account
  cannot write, so Claude cannot tamper with a script you run.
- `claude-session.ps1` runs under the **Claude** account. It lives in `C:\ProgramData\ClaudeHere`,
  with permissions that let the Claude account read it but not modify it.
- Everything is installed per user: no administrator rights, no system-wide changes.

## Requirements

- A local account dedicated to Claude, not an administrator, that has been signed in to at least once.
- Under that account: Windows Terminal and Claude Code.

## Install

1. Download the zip of the latest version from the
   [Releases](https://github.com/lhervier/claude-here/releases) page ("Source code (zip)"),
   or with **Code > Download ZIP** on the repository page.
2. **Extract the zip** to a folder of your choice. Do not run the installer from inside the zip:
   Windows would extract `installer.cmd` alone and it would not find its scripts.
3. Double-click `installer.cmd`, from **your** account (no administrator rights needed).

Windows may warn that the file comes from the Internet: confirm to continue. To avoid the warning,
right-click the zip > Properties > check **Unblock** before extracting it.

The installer lists the local accounts and asks which one to run Claude under, then:

- copies the launcher (filled-in `claude-here.ps1` and `claude-here.cmd`) to
  `%LOCALAPPDATA%\Programs\ClaudeHere`, and adds that folder to your PATH;
- copies `claude-session.ps1` to `C:\ProgramData\ClaudeHere`, readable by the Claude account but
  not modifiable by it;
- adds the context menu entry. On Windows 11, it is under "Show more options"
  (or Shift+right-click).

Running the installer again updates the installation.

## Usage

- Right-click a folder, the empty space inside a folder, or a drive: "Open Claude here".
- In a console: `claude-here [folder]` (current folder by default).

The Claude account's password is asked for on each launch (`runas`). The folder must be
accessible to that account: not inside your profile.

Windows Terminal and Claude Code must be installed under the Claude account: `claude-here` looks
for them on that account's PATH, then in `%USERPROFILE%\Tools\WindowsTerminal` and
`%USERPROFILE%\.local\bin`, and tells you which one is missing.

## Uninstall

```powershell
.\installer.cmd -Uninstall
```

## Files

| File                 | Purpose                                                                 |
| -------------------- | ----------------------------------------------------------------------- |
| `installer.cmd`      | Runs `installer.ps1` (double-click).                                    |
| `installer.ps1`      | Installs, updates or uninstalls.                                        |
| `claude-here.ps1`    | Launcher template (your account): the installer fills in the account.   |
| `claude-session.ps1` | Runs under the Claude account: checks requirements, then starts Claude. |
