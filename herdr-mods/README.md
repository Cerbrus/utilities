# herdr-mods

The mods and layout for the [Herdr](https://herdr.dev) desktop app live in their own repository: **[Cerbrus/herdr-mods](https://github.com/Cerbrus/herdr-mods)**. Everything about them is documented there.

## Install

```powershell
.\Install.ps1
```

Clones that repository to `C:\DEV\~Cerbrus\herdr-mods` (next to this one), or pulls it when it is already there, and runs its `Install.ps1`, which installs every mod with the Borderless Layout. Non-elevated and idempotent; skipped when the Herdr app or git is missing. Set `HERDR_MODS_DIR` to keep the clone somewhere else.

To install one mod, or to work on them, use that repository directly.

## Related

[claude-statusline](../claude-statusline/README.md) writes the context percentage that the Agent Cards mod shows as a bar per agent.
