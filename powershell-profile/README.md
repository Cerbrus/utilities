# PowerShell profile

PowerShell profile providing a shortcut to launch `claude` in a project: pick a folder under `C:\DEV` and Claude Code starts there.

## What it does

- **`dev [folder]`** (alias: **`agent`**) — jump to a project folder under `C:\DEV` and launch `claude` there.
    - `dev` with no argument opens an interactive picker (arrow keys, type-to-filter, `1`-`9` quick select, `Esc` to cancel).
    - `dev util` with a partial name suggests matching folders; a single match asks `Y/n`, multiple matches open the picker pre-filtered.
    - Tab completion on the folder argument.
- **`Select-DevFolder`** — the reusable console picker behind `dev` (scrolling viewport, filter status line).

## Install

Run the installer (no admin required):

```powershell
.\Install.ps1
```

It detects the installed PowerShell editions (Windows PowerShell 5.1 always; PowerShell 7+ if `pwsh` is found) and, for each one, writes a stub profile that dot-sources the repo file — so this repo stays the single source of truth. It is idempotent: an existing dot-source line (or a symlink already pointing at the repo profile) is left alone, and a profile with other content gets the dot-source line appended rather than overwritten.

### Manual alternative: symlink

If you prefer a symlink, run this from an **elevated** PowerShell (symlink creation requires admin unless Developer Mode is enabled):

```powershell
New-Item -ItemType SymbolicLink -Path $PROFILE -Target 'C:\DEV\utilities\powershell-profile\Microsoft.PowerShell_profile.ps1' -Force
```

`$PROFILE` differs per PowerShell edition — run the command in each edition you use:

- Windows PowerShell 5.1: `C:\Users\<user>\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`
- PowerShell 7+: `C:\Users\<user>\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`

## Verify

```powershell
Get-Content $PROFILE   # should show (or dot-source) the repo profile
. $PROFILE             # reload in current session
dev                    # picker should appear
```
