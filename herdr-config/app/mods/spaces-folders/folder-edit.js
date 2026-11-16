// A spaces folder's menu and dialogs: the list opens its own mod as an overlay
// with these props, and main.js hands that copy to this class.
// props { mode: "menu", folder }: a popup with New space, New folder, Rename,
//   Move to, Move up, Move down, Delete. Delete is only offered for an empty folder.
// props { mode: "move", folder }: a popup with the places the folder can move to.
// props { mode: "name", folder?, parent? }: a dialog that renames `folder`, or
//   names a new folder under `parent` (none: at the top level).

import { div, svg } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { props, closeOverlay, openOverlay, theme, spaces } from "herdr";
import { state, walk, depthOf, parentOf, childrenOf, fits, emptyFolder, addFolder, renameFolder, removeFolder, moveFolder, placeFolder, MAX_DEPTH } from "./folders.js";

const CHROME = "mods/workspace-chrome";
const open = (mode, more, popup) => openOverlay({ mod: "spaces-folders", ...(popup ? { kind: "popup", width: 240, height: 320 } : { kind: "dialog", width: 420, height: 200 }), props: { mode, ...more } });

export class FolderEdit {
  init(cx) {
    const p = props() ?? {};
    this.at = 0;
    this.handle = cx.focus_handle();
    if (p.mode !== "name") { this.handle.focus(); return; }
    this.text = state().folders.find((f) => f.id === p.folder)?.name ?? "";
    this.input = InputState.new({ value: this.text, placeholder: "Folder name" });
    if (this.text) this.input.set_selected_range({ start: 0, end: this.text.length });
    this.input.on("change", (_e, cx) => { this.text = this.input.value(); cx.notify(); });
    this.input.on("submit", () => this.save());
    this.input.focus();
    cx.timer.after(600, () => this.input.focus());
  }

  close() {
    closeOverlay(props().overlay);
  }

  save() {
    const p = props();
    const name = this.text.trim();
    if (!name) return;
    this.close();
    if (p.folder) renameFolder(p.folder, name);
    else addFolder(name, p.parent ?? null);
  }

  // Each item: { label, icon, run?, hint?, indent?, rule? }; one without `run` is shown but can't be chosen.
  items() {
    const p = props();
    const id = p.folder;
    const st = state();
    if (p.mode === "move") {
      const parent = parentOf(st, id);
      return [
        ...(parent ? [{ label: "Top level", icon: `${CHROME}/layers.svg`, run: () => placeFolder(id, null) }] : []),
        ...walk(st).filter((f) => f.id !== parent && fits(st, id, f.id))
          .map((f) => ({ label: f.name, icon: `${CHROME}/folder.svg`, indent: depthOf(st, f.id) - 1, run: () => placeFolder(id, f.id) })),
      ];
    }
    const siblings = childrenOf(st, parentOf(st, id)).map((f) => f.id);
    const at = siblings.indexOf(id);
    const empty = emptyFolder(st, id, spaces());
    return [
      { label: "New space", icon: `${CHROME}/plus.svg`, run: () => openOverlay({ mod: "space-open", kind: "dialog", width: 560, height: 0.7, props: { folder: id } }) },
      ...(depthOf(st, id) < MAX_DEPTH ? [{ label: "New folder", icon: `${CHROME}/folder-plus.svg`, run: () => open("name", { parent: id }) }] : []),
      { label: "Rename", icon: `${CHROME}/square-pen.svg`, rule: true, run: () => open("name", { folder: id }) },
      { label: "Move to…", icon: `${CHROME}/folder.svg`, run: () => open("move", { folder: id }, true) },
      ...(at > 0 ? [{ label: "Move up", icon: "mods/spaces-folders/chevron-up.svg", run: () => moveFolder(id, -1) }] : []),
      ...(at >= 0 && at < siblings.length - 1 ? [{ label: "Move down", icon: `${CHROME}/chevron-down.svg`, run: () => moveFolder(id, 1) }] : []),
      { label: "Delete", icon: `${CHROME}/x.svg`, rule: true, ...(empty ? { run: () => removeFolder(id, spaces()) } : { hint: "not empty" }) },
    ];
  }

  choose(i) {
    const it = this.items()[i];
    if (!it?.run) return;
    this.close();
    it.run();
  }

  menu(t) {
    const list = this.items();
    const step = (by) => {
      if (!list.some((it) => it.run)) return;
      do this.at = (this.at + by + list.length) % list.length; while (!list[this.at].run);
    };
    return v_flex().id("folder-menu").track_focus(this.handle).w_full().min_h(0).p(5).bg(t.popover).text_size(12.8)
      .on_key_down((e, cx) => {
        if (e.key === "down") step(1);
        else if (e.key === "up") step(-1);
        else if (e.key === "enter") this.choose(this.at);
        else if (e.key === "escape") this.close();
        else return;
        cx.notify();
      })
      .when(!list.length, (el) => el.child(div().px(8).py(8).text_color(t.dim).child("Nowhere to move it to")))
      .children(list.map((it, i) => v_flex().flex_none()
        .when(Boolean(it.rule), (el) => el.child(div().mx(7).my(4).h(1).bg(t.border)))
        .child(h_flex().id(`fm-${i}`).h(31).pl(8 + (it.indent ?? 0) * 14).pr(8).gap(9).rounded(7).items_center()
          .text_color(it.run ? t.foreground : t.dim)
          .when(Boolean(it.run) && i === this.at, (el) => el.bg(t.selected))
          .when(Boolean(it.run), (el) => el.hover((s) => s.bg(t.hover)))
          .on_click(() => this.choose(i))
          .child(svg(it.icon).size(14).flex_none().text_color(it.run ? t.muted : t.dim))
          .child(div().flex_1().min_w(0).truncate().child(it.label))
          .when(Boolean(it.hint), (el) => el.child(div().flex_none().text_size(11).text_color(t.dim).child(it.hint))))));
  }

  render() {
    const t = theme();
    const p = props() ?? {};
    if (p.mode !== "name") return this.menu(t);
    const button = (id, text, primary, action) => h_flex().id(id).h(32).px(14).items_center().rounded(8)
      .border_1().border_color(primary ? t.solid : t.input).bg(primary ? t.solid : t.raised)
      .text_color(primary ? t.solid_foreground : t.foreground).text_size(12.5).font_medium().cursor_pointer()
      .hover((s) => s.opacity(0.88)).on_click(action).child(text);
    return v_flex().id("folder-name").track_focus(this.handle)
      .on_key_down((e, cx) => { if (e.key === "escape") { this.close(); cx.stop_propagation(); } })
      .w_full().min_h(0).p(18).bg(t.popover).text_color(t.foreground)
      .child(h_flex().items_center()
        .child(div().flex_1().text_size(15).font_semibold().child(p.folder ? "Rename folder" : "New folder"))
        .child(div().text_size(11).text_color(t.dim).child("Esc")))
      .child(div().pt(16).pb(7).text_size(11.5).text_color(t.dim).child("Name"))
      .child(Input.new(this.input).h(36).px(10).rounded(9).border_1().border_color(t.accent).bg(t.background).text_size(12.8).text_color(t.foreground))
      .child(h_flex().pt(20).gap(8).justify_end()
        .child(button("fn-cancel", "Cancel", false, () => this.close()))
        .child(button("fn-save", "Save", true, () => this.save())));
  }
}
