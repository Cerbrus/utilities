# utilities

Personal Windows utilities. One folder per utility, each self-contained with its own `README.md` and `Install.ps1`.

## Install

Prerequisite: [git](https://git-scm.com/) (authentication is handled by Git Credential Manager, which ships with Git for Windows). If [Claude Code](https://claude.com/claude-code) is missing, the installer offers to install it; individual utilities check their own dependencies and skip (with a message) when one is missing.

Run in PowerShell:

```powershell
git clone https://github.com/Cerbrus/utilities.git C:\DEV\utilities; powershell -ExecutionPolicy Bypass -File C:\DEV\utilities\Install.ps1
```

Safe to re-run: if the repo is already cloned the `git clone` is a harmless no-op error, after which `Install.ps1` pulls the latest changes and re-runs every utility's installer (all idempotent). So the same one-liner also serves as "update this machine".

From an existing clone, just run:

```powershell
.\Install.ps1
```

Everything runs non-elevated; no admin prompt required.

## Utilities

| Utility | Description |
|---------|-------------|
| [claude-statusline](claude-statusline/README.md) | Status line for Claude Code: branch, model, context usage, rate limits |
| [powershell-profile](powershell-profile/README.md) | Shortcut to launch `claude` in a project folder (default `C:\DEV`), via an interactive picker (`dev` / `agent`) |
| [wifi-mute](wifi-mute/README.md) | Mutes/unmutes audio automatically when connecting to configured Wi-Fi networks |

## Adding a utility

1. Create a new folder at the repo root with the utility's files and a `README.md`.
2. Add an `Install.ps1` in that folder:
   - non-elevated (no admin),
   - idempotent (re-running updates/overwrites cleanly),
   - standalone (resolve paths via `$PSScriptRoot`, never the current directory),
   - Windows PowerShell 5.1 compatible.
3. Done — the root `Install.ps1` auto-discovers and runs it. No root changes needed.
