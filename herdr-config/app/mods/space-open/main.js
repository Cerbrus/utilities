// Opens a folder as a space. Lists the folders under the roots in roots.js,
// narrowed by what is typed; a typed full path is offered as it is. Enter
// opens the chosen folder as a new space running ARGV, or shows the space that
// is already open there. Up/down move, Esc closes. Opened with props { folder }
// (a spaces folder's id), the new space goes into that folder.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, InputState, Input, ScrollHandle } from "gpui-base";
import { spaces, run, exec, theme, props, closeOverlay, checking, shared, setShared } from "herdr";
import { ROOTS, ARGV } from "./roots.js";

const ROW = 32, AROUND = 150, WINDOW_SHARE = 0.7;

const same = (path) => String(path ?? "").replace(/\//g, "\\").replace(/\\+$/, "").toLowerCase();
const leaf = (path) => path.replace(/[\\/]+$/, "").split(/[\\/]/).pop();
const typedPath = (text) => /^([a-z]:[\\/]|\\\\|~[\\/])/i.test(text);

export default class SpaceOpen extends View {
  init(_props, cx) {
    this.text = "";
    this.at = 0;
    this.folders = [];
    this.loading = true;
    this.scroll = ScrollHandle.new();
    this.handle = cx.focus_handle();
    this.input = InputState.new({ placeholder: "Folder to open…" });
    this.input.on("change", (_e, cx) => { this.text = this.input.value(); this.at = 0; this.scroll.scroll_to_item(0); cx.notify(); });
    this.input.on("submit", () => this.go(this.rows()[this.at]));
    this.input.focus();
    cx.timer.after(600, () => this.input.focus());
    if (checking()) return;
    cx.spawn(async (cx) => {
      const found = [];
      for (const root of ROOTS) {
        try {
          const r = await exec("cmd", ["/d", "/c", "dir", "/b", "/ad", root.path]);
          if (r.code !== 0) continue;
          for (const name of r.stdout.split(/\r?\n/).map((n) => n.trim()).filter(Boolean)) {
            found.push({ name, label: root.label ? `${root.label}/${name}` : name, path: `${root.path}\\${name}` });
          }
        } catch {}
      }
      this.folders = found.sort((a, b) => a.label.localeCompare(b.label, undefined, { sensitivity: "base" }));
      this.loading = false;
      cx.notify();
    });
  }

  close() {
    closeOverlay(props().overlay);
  }

  rows() {
    const text = this.text.trim();
    const needle = text.toLowerCase();
    const listed = this.folders
      .filter((f) => f.label.toLowerCase().includes(needle))
      .sort((a, b) => Number(!a.name.toLowerCase().startsWith(needle)) - Number(!b.name.toLowerCase().startsWith(needle)));
    if (!typedPath(text) || listed.some((f) => same(f.path) === same(text))) return listed;
    return [{ name: leaf(text), label: text, path: text.replace(/\//g, "\\"), typed: true }, ...listed];
  }

  go(row) {
    if (!row) return;
    this.close();
    const open = spaces().find((s) => !s.machine && same(s.folder) === same(row.path));
    if (open) run("space.select", { id: open.id });
    else {
      const folder = props().folder;
      if (folder) setShared("spaces.folders.incoming", { folder, path: same(row.path), at: Date.now() });
      run("space.new", { name: row.name, folder: row.path, argv: ARGV });
    }
  }

  render() {
    const t = theme();
    const rows = this.rows();
    const open = new Set(spaces().filter((s) => !s.machine).map((s) => same(s.folder)));
    const into = (shared("spaces.folders")?.folders ?? []).find((f) => f.id === props()?.folder)?.name;
    const room = Math.max(ROW * 4, Math.floor((window.viewport_size().height * WINDOW_SHARE - AROUND) / ROW) * ROW);
    return v_flex().id("space-open").track_focus(this.handle).w_full().min_h(0).p(18).gap(10).bg(t.popover).text_size(13)
      .on_key_down((e, cx) => {
        if (e.key === "escape") return this.close();
        if (!rows.length || (e.key !== "down" && e.key !== "up")) return;
        this.at = (this.at + (e.key === "down" ? 1 : rows.length - 1)) % rows.length;
        this.scroll.scroll_to_item(this.at);
        cx.stop_propagation();
        cx.notify();
      })
      .child(h_flex().items_center()
        .child(div().flex_1().text_size(15).font_semibold().text_color(t.foreground).child(into ? `Open a space in ${into}` : "Open a space"))
        .child(div().text_size(11).text_color(t.dim).child("Esc")))
      .child(h_flex().h(36).flex_none().px(10).gap(8).items_center().rounded(9).border_1().border_color(t.accent).bg(t.background)
        .child(svg("mods/workspace-chrome/search.svg").size(15).text_color(t.dim))
        .child(Input.new(this.input).flex_1().h_full().text_size(12.8).text_color(t.foreground)))
      .child(v_flex().id("so-list").h(Math.min(room, Math.max(1, rows.length) * ROW)).min_h(0).overflow_y_scrollbar().track_scroll(this.scroll)
        .when(!rows.length, (el) => el.child(div().px(10).py(8).text_color(t.dim)
          .child(this.loading ? "Looking for folders…" : "No folder matches. Type a full path to open it.")))
        .children(rows.map((r, i) => h_flex().id(`so-${i}`).h(ROW).flex_none().px(10).gap(10).rounded(7).items_center().cursor_pointer()
          .when(i === this.at, (el) => el.bg(t.selected))
          .hover((s) => s.bg(t.hover))
          .on_click(() => this.go(r))
          .child(svg(`mods/workspace-chrome/${r.typed ? "folder-plus" : "folder"}.svg`).size(14).flex_none().text_color(t.muted))
          .child(div().flex_1().min_w(0).truncate().text_color(t.foreground).child(r.label))
          .when(open.has(same(r.path)), (el) => el.child(div().flex_none().text_size(11).text_color(t.dim).child("open"))))));
  }
}
