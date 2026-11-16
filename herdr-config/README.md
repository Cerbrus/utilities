# herdr-config

[herdr](https://herdr.dev) customization: the terminal herdr config and the Herdr app layout and mods.

## What is in here

| Path | Goes to | What it is |
|---|---|---|
| `terminal/config.toml` | `%APPDATA%\herdr\config.toml` | Terminal herdr: theme colors, sidebar agent rows (model and context bar), sounds off. |
| `app/layouts/main-folders.json` | `~\.config\herdr-app\layouts\` | Clone of the shipped `main` layout that shows the `spaces-folders` mod in the sidebar. |
| `app/mods/spaces-folders/` | `~\.config\herdr-app\mods\` | Clone of the shipped `spaces` mod that draws the spaces list as a file tree of collapsible folders. |

### Spaces folders

`app/mods/spaces-folders/folders.js` lists the folders and decides where a space goes:

```js
export const FOLDERS = [
  { name: "Asito", fallback: true },
  { name: "Personal", under: ["C:/DEV/~Cerbrus"] },
];
```

A space goes to the folder with the longest `under` path its own folder is inside. A space that matches none goes to the `fallback` folder; without a fallback it stays loose below the folders. Spaces are also reordered so each folder's spaces sit together. Click a folder header to fold it.

Both clones were made from Herdr app 0.1.16 (`cloned_from` in the files). Herdr never updates clones, so changes to the shipped `main` layout or `spaces` mod have to be merged in by hand.

## Install

```powershell
.\Install.ps1
```

Copies every file to its place. Non-elevated and idempotent; a part whose herdr is not installed is skipped. Afterwards:

```powershell
herdr server reload-config                        # terminal herdr
herdr-app do layout.switch --name main-folders    # Herdr app
```

## Changing things

The Herdr app reloads a mod or layout when its live file is saved, so edit the live file, check it, then pull it into the repo:

```powershell
herdr-app check $HOME\.config\herdr-app\mods\spaces-folders
.\Install.ps1 -Pull
```

`-Pull` copies the live files back over the repo's copies, including new `.js`, `.json` and `.svg` files in a mod folder that is already in the repo.

## Related

The hook that starts `claude` in new terminal herdr panes is part of [powershell-profile](../powershell-profile/README.md), and [claude-statusline](../claude-statusline/README.md) reports model and context to herdr.
