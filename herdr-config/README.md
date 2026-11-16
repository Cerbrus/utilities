# herdr-config

[herdr](https://herdr.dev) customization: the terminal herdr config and the Herdr app layout and mods.

## What is in here

| Path | Goes to | What it is |
|---|---|---|
| `terminal/config.toml` | `%APPDATA%\herdr\config.toml` | Terminal herdr: theme colors, sidebar agent rows (model and context bar), sounds off. |
| `app/layouts/main-folders.json` | `~\.config\herdr-app\layouts\` | Clone of the shipped `main` layout that shows the `spaces-folders` mod in the sidebar, with square panes and panels that sit flush, 1px lines between them. A tab's only pane has no header or focus ring. |
| `app/mods/spaces-folders/` | `~\.config\herdr-app\mods\` | Clone of the shipped `spaces` mod that draws the spaces list as a file tree of collapsible folders. |
| `app/mods/space-open/` | `~\.config\herdr-app\mods\` | Picker that opens a folder as a new space running `claude`. |
| `app/mods/files-flat/`, `app/mods/changes-flat/` | `~\.config\herdr-app\mods\` | Clones of the shipped `files` and `changes` panels without their rounded border; the layout draws the lines between them. |
| `app/mods/agents-bots/` | `~\.config\herdr-app\mods\` | Clone of the shipped `agents` list that shows each agent as a card: a robot avatar, a context bar, the time since its status changed and the status. |

### Spaces folders

Folders are made and filled by hand; a space outside every folder is loose and shows above them. Inside a folder its spaces come first, then its subfolders.

- **New folder**: the folder button next to `+` in the Spaces header, or "New folder" in a folder's right-click menu for one inside it. Folders nest three levels deep at most.
- **Right-click a folder header**: New space (opens the picker; the space lands in that folder), New folder, Rename, Move to, Move up, Move down, Delete. Delete is only offered when no space is in the folder or under it; its empty subfolders go with it.
- **Move a folder**: drag its header onto another header. The top or bottom edge puts it before or after that folder, the middle puts it inside.
- **Fold**: click a folder header; a folded folder hides everything under it. Folded folders open by themselves when you go to a space, tab or agent inside them. Which folders are folded is kept in `~\.config\herdr-app\data\spaces-folders\store.json`.
- **Move a space**: drag it onto a folder header or onto a space inside that folder. Drag it onto a loose space, or below the list, to take it out of its folder.

Spaces are reordered so each folder's spaces sit together. The folders and which space is in which are app state (`spaces.folders` in `~\.config\herdr-app\shared.json`), not files in this repo. On a first run `folders.js` seeds an `Asito` folder (spaces named `asito-*` or `mtp-*`) and a `Personal` folder (spaces under `~Cerbrus`).

### Agent cards

Each agent's avatar is a [DiceBear](https://www.dicebear.com) `voxel-bot` in the Night Shift colours, mirrored and on a transparent background, the same one for the same space and tab. `agents-bots` fetches it once from `api.dicebear.com`, sending only a hash of the space and tab name as the seed, and keeps it in `~\.config\herdr-app\data\agents-bots\avatars\`. The avatar bobs while the agent works, shakes sideways in bursts when it needs you and is dimmed while it is idle.

The context bar reads `~\.config\herdr-app\data\claude-statusline\<terminal id>.json`, written by `claude-statusline\pr-statusline.ps1`; it stays empty until that agent's status line has drawn once. An agent that has been idle for more than a day moves to a folded `Inactive` group at the bottom, unless it is pinned or shown. Sorting, pinning, sub-agents and the narrow rail work as in the shipped list.

### Opening a space

The `+` in the Spaces header and `ctrl-shift-n` open the `space-open` picker: the folders under the roots in `app/mods/space-open/roots.js`, narrowed as you type; a typed full path is offered as it is. Enter opens the folder as a space that runs `ARGV` from the same file (`claude`), or shows the space already open there. The new space is loose, unless the picker was opened from a folder's right-click menu.

`Install.ps1` rebinds `ctrl-shift-n` in the app's `keys.json` from `space.new` to the picker. "New space" in the tab bar's `+` menu and in the command palette is still Herdr's own and starts a plain shell.

The layout and the `spaces-folders`, `files-flat`, `changes-flat` and `agents-bots` mods were cloned from Herdr app 0.1.16 (`cloned_from` in the files). Herdr never updates clones, so changes to the shipped `main` layout or `spaces`, `files`, `changes` and `agents` mods have to be merged in by hand.

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

`-Pull` copies the live files back over the repo's copies, including new `.js`, `.json` and `.svg` files in a mod folder that is already in the repo. A new mod folder has to be copied into `app/mods/` by hand once.

## Related

Two terminal herdr integrations live elsewhere in this repo: the hook that starts `claude` in new panes is part of [powershell-profile](../powershell-profile/README.md), and [claude-statusline](../claude-statusline/README.md) reports model and context usage to the sidebar. Neither applies to the Herdr app, which sets no `HERDR_*` variables.
