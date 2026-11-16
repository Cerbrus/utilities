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

`pr-statusline.ps1` renders Claude Code's status line from the session JSON piped to stdin (branch, model, context bar, rate limits, caveman-mode flag). `Install.ps1` rewrites the `statusLine` entry in Claude Code's `settings.json` (respects `$env:CLAUDE_CONFIG_DIR`, defaults to `~\.claude`) to point at the repo copy, preserving all other settings via a JSON round-trip.

### herdr-config

Repo copies of herdr files; `Install.ps1` copies them to where herdr reads them (`%APPDATA%\herdr\config.toml` for terminal herdr, `~\.config\herdr-app` for the Herdr app) and `Install.ps1 -Pull` copies live edits back. The app hot-reloads live files, so mod work happens in place and is pulled afterwards. `app/mods/spaces-folders` and `app/layouts/main-folders.json` are clones of the shipped `spaces` mod and `main` layout: the app never updates clones, and shipped mods must not be edited directly. `app/mods/space-open` is our own mod (the new-space picker). Verify a mod with `herdr-app check <mod folder>` and `herdr-app shot`; the app's own reference is `~\.config\herdr-app\AGENTS.md`.

Things the app's docs don't say, learned the hard way:

- A mod cannot import from another mod's folder (`../other/x.js` is refused), which is why the folder menu and dialogs live inside `spaces-folders` (`folder-edit.js`) and that mod opens itself as an overlay with `props.mode`. Mods share data through `shared()` / `setShared()` instead: `spaces.folders` holds the folders, `spaces.folders.incoming` is how `space-open` tells the list which folder a new space belongs in.
- A popup is as tall as its content, so a scroll container (`overflow_y_scrollbar` with `min_h(0)`) inside one collapses to nothing and the popup shows empty.
- `cx.notify()` in a mouse-down handler redraws the element and swallows its `on_click`. Folder headers therefore fold on mouse-up, comparing against the header that was pressed.
- Elements only exist after a redraw: the drop zones on folder headers are drawn while a header is held, so the press has to `cx.notify()`.
- `herdr-app check` passes on mods that render nothing or mis-handle input; it only proves the mod loads. Clicking, dragging and popups need a person or a screenshot.

### wifi-mute

Chain: Wi-Fi connect → Windows logs event 8001 to `Microsoft-Windows-WLAN-AutoConfig/Operational` → one scheduled task per SSID (XPath event subscription, built via the `MSFT_TaskEventTrigger` CIM class because `New-ScheduledTaskTrigger` can't do event triggers) → runs `Set-Mute.ps1` by absolute path.

- `Set-Mute.ps1` drives CoreAudio (`IAudioEndpointVolume`) through inline C# COM interop. The interface declarations bind by **vtable position** — the dummy `_1()`.. `_11()` padding methods must not be touched. Parameters are `[int]` not `[bool]` because `powershell.exe -File` can't pass `$true`.
- `networks.json` (next to the scripts) holds the machine-specific SSID list — git-ignored via the root `.gitignore`, created interactively by `Install.ps1` on first run or `-Reconfigure`. Task names follow `WiFi Mute - <SSID>` / `WiFi Unmute - <SSID>`; the installer removes all matching tasks before re-registering so deleted networks clean up.
- Toasts borrow Windows PowerShell's AUMID, so no app registration is needed.

Manual test without switching networks: `Start-ScheduledTask 'WiFi Mute - <SSID>'`, or `.\Set-Mute.ps1 -Mute 1` directly.
