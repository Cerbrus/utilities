# PowerShell profile

PowerShell profile with an interactive project picker for `C:\DEV`.

## What it does

- **`dev [folder]`** (alias: **`agent`**) — jump to a project folder under `C:\DEV` and launch `claude` there.
    - `dev` with no argument opens an interactive picker (arrow keys, type-to-filter, `1`-`9` quick select, `Esc` to cancel).
    - `dev util` with a partial name suggests matching folders; a single match asks `Y/n`, multiple matches open the picker pre-filtered.
    - Tab completion on the folder argument.
- **`Select-DevFolder`** — the reusable console picker behind `dev` (scrolling viewport, filter status line).

## Install

The profile is used via a symlink so this repo stays the single source of truth.

From an **elevated** PowerShell (symlink creation requires admin unless Developer Mode is enabled):

```powershell
New-Item -ItemType SymbolicLink -Path $PROFILE -Target 'C:\DEV\utilities\powershell-profile\Microsoft.PowerShell_profile.ps1' -Force
```

`$PROFILE` differs per PowerShell edition — run the command in each edition you use:

- Windows PowerShell 5.1: `C:\Users\<user>\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`
- PowerShell 7+: `C:\Users\<user>\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`

### No-admin alternative

Instead of a symlink, create a stub profile that dot-sources the repo file:

```powershell
Set-Content $PROFILE '. C:\DEV\utilities\powershell-profile\Microsoft.PowerShell_profile.ps1'
```

## Verify

```powershell
Get-Item $PROFILE | Select-Object LinkType, Target   # symlink check
. $PROFILE                                           # reload in current session
dev                                                  # picker should appear
```
