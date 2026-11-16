import { View, div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input, Scrollbar } from "gpui-base";
import { keys, commands, theme } from "herdr";

const MODIFIERS = ["ctrl", "alt", "shift", "cmd", "fn"];
const MODIFIER_LABELS = { ctrl: "Ctrl", alt: "Alt", shift: "Shift", cmd: "Win", fn: "Fn" };
const KEY_LABELS = { left: "←", right: "→", up: "↑", down: "↓", pageup: "PgUp", pagedown: "PgDn", backspace: "Backspace", insert: "Ins", delete: "Del", escape: "Esc", enter: "Enter", tab: "Tab", space: "Space" };
const GROUPS = ["space", "tab", "pane", "agent", "terminal", "layout", "app", "mod"];
const MOD_COMMANDS = { "agents-bots.top": { group: "agent", label: "Show the agent at the top of the Agents list" } };
const GROUP_LABELS = { space: "Spaces", tab: "Tabs", pane: "Panes", agent: "Agents", terminal: "Terminal", layout: "Layout", app: "App", mod: "Mods", other: "Other" };

function chord(text) {
  const modifiers = [];
  let key = text;
  for (;;) {
    const modifier = MODIFIERS.find((name) => key.startsWith(`${name}-`) && key.length > name.length + 1);
    if (!modifier) break;
    modifiers.push(modifier);
    key = key.slice(modifier.length + 1);
  }
  return { modifiers, key };
}

const signature = ({ modifiers, key }) => `${[...modifiers].sort().join("-")}+${key}`;
const keyLabel = (key) => KEY_LABELS[key] ?? (key.length === 1 ? key.toUpperCase() : key[0].toUpperCase() + key.slice(1));

function sectionLabel(section) {
  if (section === "global") return "Everywhere";
  if (section === "terminal") return "In a terminal";
  if (section.startsWith("layout:")) return `In the ${section.slice(7)} layout`;
  return section.startsWith("mod:") ? `In ${section.slice(4)}` : section;
}

function describe(action, about) {
  if (action === "terminal") return { group: "terminal", label: "Goes to the program" };
  if (action.startsWith("send:")) return { group: "terminal", label: "Types a control sequence into the program" };
  const split = action.indexOf(":"), name = split < 0 ? action : action.slice(0, split), detail = split < 0 ? null : action.slice(split + 1);
  if (MOD_COMMANDS[name]) return { ...MOD_COMMANDS[name], detail, name };
  const group = name.split(".")[0], text = about.get(name);
  return { group: GROUPS.includes(group) ? group : "other", label: text ? text.split(/\. | \(|, | to the "/)[0].replace(/\.$/, "") : name, detail, name };
}

function entries() {
  const about = new Map(commands().map((command) => [command.name, command.about]));
  const found = new Map();
  for (const binding of keys()) {
    const pressed = chord(binding.keys), described = describe(binding.action, about);
    const numbered = described.detail !== null && /^\d$/.test(described.detail ?? "") && pressed.key === described.detail;
    const id = numbered ? `${binding.section}|${described.name}|#${pressed.modifiers.join("-")}` : `${binding.section}|${binding.action}`;
    if (!found.has(id)) found.set(id, { id, section: binding.section, ...described, detail: numbered ? null : described.detail, chords: [], signatures: new Set(), digits: numbered ? [] : null, modifiers: pressed.modifiers });
    const entry = found.get(id);
    entry.signatures.add(signature(pressed));
    if (numbered) entry.digits.push(Number(pressed.key));
    else entry.chords.push(pressed);
  }
  for (const entry of found.values()) {
    if (entry.digits) entry.chords.push({ modifiers: entry.modifiers, key: `${Math.min(...entry.digits)}–${Math.max(...entry.digits)}` });
  }
  return [...found.values()];
}

export default class Cheatsheet extends View {
  init() {
    this.query = "";
    this.input = InputState.new({ placeholder: "Filter shortcuts" });
    this.input.on("change", (_e, cx) => { this.query = this.input.value().trim().toLowerCase(); cx.notify(); });
  }

  chip(text, t) {
    return div().flex_none().h(20).min_w(20).px(5).flex().items_center().justify_center().rounded(4).border_1()
      .border_color(t.border).bg(t.raised).text_size(11).child(text);
  }

  row(entry, t) {
    return h_flex().id(`key-${entry.id}`).min_h(30).flex_none().px(8).py(4).gap(8).items_center().rounded(6)
      .hover((s) => s.bg(t.hover))
      .child(h_flex().flex_1().min_w(0).gap(5).items_center()
        .child(div().min_w(0).truncate().text_color(t.muted).child(entry.label))
        .when(Boolean(entry.detail), (el) => el.child(div().flex_none().max_w(110).truncate().text_color(t.dim).child(entry.detail))))
      .child(v_flex().flex_none().gap(3).items_end().children(entry.chords.map((pressed) => h_flex().gap(3)
        .children(pressed.modifiers.map((modifier) => this.chip(MODIFIER_LABELS[modifier], t)))
        .child(this.chip(keyLabel(pressed.key), t)))));
  }

  render() {
    const t = theme(), query = this.query;
    const shown = entries().filter((entry) => !query || `${entry.label} ${entry.detail ?? ""} ${entry.name ?? ""} ${[...entry.signatures].join(" ")}`.toLowerCase().includes(query));
    const sections = [...new Set(shown.map((entry) => entry.section))];
    const rows = sections.flatMap((section) => [
      div().px(8).pt(12).pb(4).flex_none().font_semibold().child(sectionLabel(section)),
      ...[...GROUPS, "other"].flatMap((group) => {
        const members = shown.filter((entry) => entry.section === section && entry.group === group);
        if (!members.length) return [];
        return [div().px(8).pt(8).pb(2).flex_none().text_size(11).text_color(t.dim).child(GROUP_LABELS[group]), ...members.map((entry) => this.row(entry, t))];
      }),
    ]);
    return v_flex().id("cheatsheet").size_full().min_h(0).overflow_hidden().bg(t.background).text_color(t.foreground).text_size(13)
      .child(h_flex().h(42).flex_none().px(14).items_center().border_b(1).border_color(t.border)
        .child(div().font_semibold().child("Keys")))
      .child(div().flex_none().p(10).border_b(1).border_color(t.border)
        .child(div().h(30).px(10).flex().items_center().rounded(8).border_1().border_color(t.border).on_mouse_down("left", (_e, cx) => cx.stop_propagation())
          .child(Input.new(this.input).h_full().text_size(12).text_color(t.foreground))))
      .child(div().flex_1().min_h(0).relative()
        .child(v_flex().id("cheatsheet-list").absolute().inset_0().overflow_y_scroll().px(6).pb(10).children(rows)
          .when(!shown.length, (el) => el.child(div().p(8).text_color(t.dim).child("No shortcut matches"))))
        .child(Scrollbar.vertical("cheatsheet-list").absolute().inset_0()));
  }
}
