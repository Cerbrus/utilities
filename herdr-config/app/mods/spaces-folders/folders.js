// The folders of the spaces list, in the order they show. A space goes to the
// folder with the longest `under` path its own folder is inside; one that
// matches none goes to the `fallback` folder, or stays loose below the folders.
export const FOLDERS = [
  { name: "Asito", fallback: true },
  { name: "Personal", under: ["C:/DEV/~Cerbrus"] },
];

const norm = (path) => String(path ?? "").replace(/\\/g, "/").replace(/\/+$/, "").toLowerCase();

export function folderOf(space) {
  if (space.machine) return null;
  const at = norm(space.folder);
  let best = null, depth = -1;
  for (const f of FOLDERS) for (const u of f.under ?? []) {
    const root = norm(u);
    if ((at === root || at.startsWith(`${root}/`)) && root.length > depth) { best = f.name; depth = root.length; }
  }
  return best ?? FOLDERS.find((f) => f.fallback)?.name ?? null;
}
