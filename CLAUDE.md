# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Personal Windows utilities, expected to live at `C:\DEV\~Cerbrus\utilities`. One folder per utility, each self-contained with its own `README.md` and `Install.ps1`. The root `Install.ps1` self-updates the repo (`git pull --ff-only`) and then auto-discovers and runs every `<utility>\Install.ps1` — adding a utility requires no root changes.

## Conventions (must hold for every utility's Install.ps1)

- **Non-elevated** — nothing may require admin. The powershell-profile installer deliberately uses a dot-sourcing stub instead of a symlink for this reason.
- **Idempotent** — re-running updates/overwrites cleanly. The root one-liner doubles as the update mechanism.
- **Standalone** — resolve paths via `$PSScriptRoot`, never the current directory.
- **Self-checking** — verify your own dependencies; on a missing hard dependency, print a message and `return` (skip) instead of throwing. Soft dependencies get a `Write-Warning` but install anyway.
- **Windows PowerShell 5.1 compatible** — no `&&`/`||` pipeline chains, no ternary/null-coalescing operators, pass `-Encoding utf8` explicitly to `Set-Content`/`Add-Content`/`Out-File`.

## Verifying changes

There is no build/lint/test tooling. Syntax-check a script without executing it:

```powershell
powershell -NoProfile -Command "[void][scriptblock]::Create((Get-Content -Raw 'path\to\script.ps1'))"
```

Do not actually run installers while developing unless asked — they modify the machine ($PROFILE files, scheduled tasks).

## Architecture notes

### powershell-profile

`Microsoft.PowerShell_profile.ps1` is the single source of truth; user profiles just dot-source it (stub written by `Install.ps1`, which detects both PS 5.1 and PS 7+ and derives Documents via `[Environment]::GetFolderPath('MyDocuments')` for OneDrive redirection). The profile is a shortcut to launch `claude`: `dev`/`agent` picks a project folder under the dev root (`$env:DEV_ROOT`, default `C:\DEV`) and starts Claude Code there, built on `Select-DevFolder`, a raw-console picker (manual cursor positioning, ANSI escapes, `[Console]::ReadKey`).

### claude-statusline

`pr-statusline.ps1` renders Claude Code's status line from the session JSON piped to stdin (branch, model, context bar, rate limits, caveman-mode flag). Inside a Herdr app pane (`HC_TERMINAL_ID`) it also writes the context percentage to `data\claude-statusline\<terminal id>.json` under the app's folder, for the `agent-cards` mod of herdr-mods. `Install.ps1` rewrites the `statusLine` entry in Claude Code's `settings.json` (respects `$env:CLAUDE_CONFIG_DIR`, defaults to `~\.claude`) to point at the repo copy, preserving all other settings via a JSON round-trip.

### herdr-mods

A pointer. The Herdr app mods and layout live in their own repository, `C:\DEV\~Cerbrus\herdr-mods` (https://github.com/Cerbrus/herdr-mods), with their own `CLAUDE.md`; mod work happens there. `Install.ps1` here clones that repository next to this one (`HERDR_MODS_DIR` overrides the place), or pulls it, and runs its `Install.ps1`. It is skipped when the Herdr app or git is missing.

### wifi-mute

Chain: Wi-Fi connect → Windows logs event 8001 to `Microsoft-Windows-WLAN-AutoConfig/Operational` → one scheduled task per SSID (XPath event subscription, built via the `MSFT_TaskEventTrigger` CIM class because `New-ScheduledTaskTrigger` can't do event triggers) → runs `Set-Mute.ps1` by absolute path.

- `Set-Mute.ps1` drives CoreAudio (`IAudioEndpointVolume`) through inline C# COM interop. The interface declarations bind by **vtable position** — the dummy `_1()`.. `_11()` padding methods must not be touched. Parameters are `[int]` not `[bool]` because `powershell.exe -File` can't pass `$true`.
- `networks.json` (next to the scripts) holds the machine-specific SSID list — git-ignored via the root `.gitignore`, created interactively by `Install.ps1` on first run or `-Reconfigure`. Task names follow `WiFi Mute - <SSID>` / `WiFi Unmute - <SSID>`; the installer removes all matching tasks before re-registering so deleted networks clean up.
- Toasts borrow Windows PowerShell's AUMID, so no app registration is needed.

Manual test without switching networks: `Start-ScheduledTask 'WiFi Mute - <SSID>'`, or `.\Set-Mute.ps1 -Mute 1` directly.
