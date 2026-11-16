// The folders of the spaces list. Kept in shared state, so the list, the folder
// menu and the folder dialogs all see one copy:
//   { folders: [{ id, name, parent? }], of: { <space id>: <folder id> } }
// Folders nest up to MAX_DEPTH levels; siblings show in the order of `folders`.
// A space is in a folder only because it was put there; one without an entry
// in `of` is loose and shows above the folders.
import { shared, setShared } from "herdr";

export const KEY = "spaces.folders";
export const MAX_DEPTH = 3;

// The folders a first run starts with, and which open spaces go into them.
const SEED = [
  { name: "Asito", takes: (s) => /^(asito|mtp)-/i.test(s.name ?? "") },
  { name: "Personal", takes: (s) => /[\\/]~cerbrus[\\/]/i.test(s.folder ?? "") },
];

const fresh = () => `f${Date.now().toString(36)}${Math.floor(Math.random() * 1296).toString(36)}`;

// A folder whose parent is gone counts as a top-level one.
export function state() {
  const s = shared(KEY);
  const ids = new Set((s?.folders ?? []).map((f) => f.id));
  return { folders: (s?.folders ?? []).map((f) => ({ ...f, parent: ids.has(f.parent) ? f.parent : null })), of: s?.of ?? {} };
}

const save = (st, folders, of = st.of) => setShared(KEY, { folders, of });

export const seeded = () => Boolean(shared(KEY));

export function seed(spaces) {
  const folders = SEED.map((f, n) => ({ id: `seed${n}`, name: f.name, parent: null }));
  const of = {};
  for (const s of spaces) {
    if (s.machine) continue;
    const at = SEED.findIndex((f) => f.takes(s));
    if (at >= 0) of[s.id] = folders[at].id;
  }
  setShared(KEY, { folders, of });
}

export const childrenOf = (st, parent) => st.folders.filter((f) => f.parent === parent);
export const parentOf = (st, id) => st.folders.find((f) => f.id === id)?.parent ?? null;

// 1 for a top-level folder.
export function depthOf(st, id) {
  let depth = 0;
  for (let at = id; at; at = parentOf(st, at)) depth += 1;
  return depth;
}

// How many levels a folder and what is under it take: 1 without subfolders.
export const heightOf = (st, id) => 1 + Math.max(0, ...childrenOf(st, id).map((f) => heightOf(st, f.id)));

// A folder's id and those of everything under it.
export const subtree = (st, id) => [id, ...childrenOf(st, id).flatMap((f) => subtree(st, f.id))];

// Every folder, each before what is under it: the order the list shows them in.
export const walk = (st, parent = null) => childrenOf(st, parent).flatMap((f) => [f, ...walk(st, f.id)]);

// Whether a folder may go under `parent` (null: the top level): not under
// itself, and its deepest level stays within MAX_DEPTH.
export function fits(st, id, parent) {
  if (parent && subtree(st, id).includes(parent)) return false;
  return depthOf(st, parent) + heightOf(st, id) <= MAX_DEPTH;
}

export function folderOf(space, st = state()) {
  const id = st.of[space.id];
  return st.folders.some((f) => f.id === id) ? id : null;
}

// Puts a space in a folder; null takes it out.
export function assign(space, folder) {
  const st = state();
  if ((st.of[space] ?? null) === folder) return;
  const of = { ...st.of };
  if (folder) of[space] = folder;
  else delete of[space];
  save(st, st.folders, of);
}

export function addFolder(name, parent = null) {
  const st = state();
  if (depthOf(st, parent) >= MAX_DEPTH) return;
  save(st, [...st.folders, { id: fresh(), name, parent }]);
}

export function renameFolder(id, name) {
  const st = state();
  save(st, st.folders.map((f) => (f.id === id ? { ...f, name } : f)));
}

// Whether no open space is in the folder or anywhere under it.
export function emptyFolder(st, id, spaces) {
  const ids = new Set(subtree(st, id));
  return !spaces.some((s) => ids.has(folderOf(s, st)));
}

// Removes an empty folder and the (empty) folders under it.
export function removeFolder(id, spaces) {
  const st = state();
  if (!emptyFolder(st, id, spaces)) return;
  const gone = new Set(subtree(st, id));
  save(st, st.folders.filter((f) => !gone.has(f.id)), Object.fromEntries(Object.entries(st.of).filter(([, folder]) => !gone.has(folder))));
}

// Moves a folder under `parent` (null: the top level), before its new sibling
// `before`, or last when there is none.
export function placeFolder(id, parent, before = null) {
  const st = state();
  const folder = st.folders.find((f) => f.id === id);
  if (!folder || before === id || !fits(st, id, parent)) return;
  const rest = st.folders.filter((f) => f.id !== id);
  const at = before ? rest.findIndex((f) => f.id === before) : -1;
  rest.splice(at < 0 ? rest.length : at, 0, { ...folder, parent });
  save(st, rest);
}

// The space-open picker leaves { folder, path, at } here when it opens a space
// from a folder's menu; the space that then appears at that path goes into the folder.
const INCOMING = "spaces.folders.incoming";
const samePath = (path) => String(path ?? "").replace(/\//g, "\\").replace(/\\+$/, "").toLowerCase();

export function claimIncoming(spaces) {
  const incoming = shared(INCOMING);
  if (!incoming) return;
  const st = state();
  const space = spaces.find((s) => !s.machine && !st.of[s.id] && samePath(s.folder) === incoming.path);
  if (space) assign(space.id, incoming.folder);
  if (space || Date.now() - incoming.at > 20000) setShared(INCOMING, null);
}

// One place up (-1) or down (1) among its siblings.
export function moveFolder(id, by) {
  const st = state();
  const parent = parentOf(st, id);
  const siblings = childrenOf(st, parent).map((f) => f.id);
  const to = siblings.indexOf(id) + by;
  if (to < 0 || to >= siblings.length) return;
  placeFolder(id, parent, by < 0 ? siblings[to] : siblings[to + 1] ?? null);
}
