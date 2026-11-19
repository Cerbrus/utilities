// JetBrains run configurations (.run/*.run.xml: .NET launch profiles, executables, npm scripts) of a folder as an accordion: pick one, run it,
// and follow every process. Processes are herdr-core terminals without a pane, found again by
// their labels; closing the tab stops them. Props: { folder, space }.
import { View, div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input, ScrollHandle } from "gpui-base";
import { exec, hc, home, theme, settings, run, props, shared, setShared, checking, spaces, panes, focused, notify, nextCommand } from "herdr";

const TICK_MS = 500, TAIL = 500, SHOWN = 80, BAR = 34, ROW = 26, NAME = 200;
const PICKS = "run-configs.picks", LIVE = "run-configs.live", CLOSE = "run-configs.close";
const BUILD = "Build";
const SPIN = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
const SUCCESS = /compiled successfully|build succeeded|now listening on|application started|watching for file changes|bundle generation complete|[✔√]/i;
const MARKS = /(https?:\/\/[^\s"'<>)\]]+)|(^\[?\d{2}:\d{2}:\d{2}(?:[.,]\d+)?|^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}\S*)|\b(INF|DBG|VRB|WRN|ERR|FTL|CRIT)\b|^(info|dbug|trce|warn|fail|crit)(?=:)/g;
const NPM = "js.build_tools.npm";
const TYPES = { CompoundRunConfigurationType: "group", LaunchSettings: ".NET", RunNativeExe: "exe", [NPM]: "npm" };
const LIST = "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false); & { param($p) "
  + "$d = Get-Item -LiteralPath $p -ErrorAction Stop; "
  + "while ($d -and -not (Test-Path -LiteralPath (Join-Path $d.FullName '.run'))) { $d = $d.Parent }; "
  + "if (-not $d) { throw \"No .run folder in $p or above\" }; "
  + "$configs = @(Get-ChildItem -LiteralPath (Join-Path $d.FullName '.run') -Filter *.run.xml | ForEach-Object { "
  + "$c = ([xml](Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8)).SelectSingleNode('/component/configuration'); "
  + "if ($c) { $o = @{}; foreach ($n in $c.SelectNodes('option')) { $o[$n.GetAttribute('name')] = $n.GetAttribute('value') }; "
  + "foreach ($n in $c.SelectNodes('package-json|command|arguments')) { $o[$n.Name] = $n.GetAttribute('value') }; "
  + "$m = 'npm'; if ($o['package-json']) { $j = Split-Path ($o['package-json'].Replace('$PROJECT_DIR$', $d.FullName)); "
  + "if (Test-Path -LiteralPath (Join-Path $j 'yarn.lock')) { $m = 'yarn' } elseif (Test-Path -LiteralPath (Join-Path $j 'pnpm-lock.yaml')) { $m = 'pnpm' } }; "
  + "@{ name = $c.GetAttribute('name'); type = $c.GetAttribute('type'); manager = $m; "
  + "scripts = @($c.SelectNodes('scripts/script') | ForEach-Object { $_.GetAttribute('value') }); "
  + "children = @($c.SelectNodes('toRun') | ForEach-Object { $_.GetAttribute('name') }); options = $o } } }); "
  + "ConvertTo-Json -Compress -Depth 5 -InputObject @{ root = $d.FullName; configs = $configs } } ";

const link = (url) => url.replace(/[.,;:]+$/, "").replace(/\/\/(0\.0\.0\.0|\+|\*)(?=[:\/]|$)/, "//localhost");
const quote = (value) => `'${value.replace(/['‘’‚‛]/g, "$&$&")}'`;
const parent = (path) => path.replace(/[\\/][^\\/]*$/, "");
const words = (text) => [...(text ?? "").matchAll(/"([^"]*)"|(\S+)/g)].map((match) => match[1] ?? match[2]);

function normalize(path) {
  const parts = [];
  for (const part of path.split(/[\\/]+/)) {
    if (part === "..") parts.pop();
    else if (part && part !== ".") parts.push(part);
  }
  return parts.join("\\");
}

function tail(text) {
  const lines = text.replace(/\r/g, "").split("\n").map((line) => line.trimEnd()).filter((line) => !line.startsWith("[hc] "));
  while (lines.length && !lines[lines.length - 1]) lines.pop();
  return lines.slice(-TAIL);
}

export default class RunConfigs extends View {
  init(given, cx) {
    this.configs = [];
    this.skipped = [];
    this.meta = new Map();
    this.state = new Map();
    this.output = new Map();
    this.finalRead = new Set();
    this.selected = null;
    this.favorites = new Set();
    this.inputs = new Map();
    this.scroll = ScrollHandle.new();
    this.open = new Set(JSON.parse(localStorage.getItem("open") ?? "[]"));
    this.turn = 0;
    const space = spaces().find((candidate) => candidate.active);
    const pane = panes().find((candidate) => candidate.pane === focused()?.pane);
    this.folder = given?.folder ?? props()?.folder ?? localStorage.getItem("folder") ?? pane?.cwd ?? space?.folder ?? home();
    localStorage.setItem("folder", this.folder);
    this.space = given?.space ?? props()?.space;
    this.started = Date.now();
    if (checking()) return;
    if (given?.config ?? props()?.config) this.selected = given?.config ?? props().config;
    this.reload(cx);
    cx.timer.every(TICK_MS, (cx) => this.tick(cx));
    cx.spawn(async (cx) => { for (;;) this.command(await nextCommand(), cx); });
  }

  command(name, cx) {
    const names = this.processes().filter((process) => !process.foreign).map((process) => process.name);
    if (name === "run") this.begin(names.filter((candidate) => !this.live(candidate)), cx);
    else if (name === "restart") this.begin(names, cx);
    else if (name === "stop") this.stop([BUILD, ...this.state.keys()], cx);
    else if (name === "expand" || name === "collapse") {
      this.open = new Set(name === "expand" ? names : []);
      localStorage.setItem("open", JSON.stringify([...this.open]));
      cx.notify();
    }
  }

  reload(cx) {
    cx.spawn(async (cx) => {
      try {
        const result = await exec("powershell", ["-NoProfile", "-Command", LIST + quote(this.folder)]);
        if (result.code) throw new Error(result.stderr.trim().split("\n")[0] || "Cannot read the run configurations");
        const found = JSON.parse(result.stdout);
        this.root = found.root;
        this.configs = [].concat(found.configs ?? []).sort((a, b) => a.name.localeCompare(b.name));
        this.error = null;
        this.favorites = new Set(this.picks().favorites ?? []);
        this.selected = [this.selected, this.picks().selected].find((name) => this.config(name)) ?? null;
      } catch (error) {
        this.error = String(error?.message ?? error);
      }
      cx.notify();
    });
  }

  picks() {
    return shared(PICKS)?.[this.root.toLowerCase()] ?? {};
  }

  pick(change) {
    setShared(PICKS, { ...shared(PICKS), [this.root.toLowerCase()]: { ...this.picks(), ...change } });
  }

  leave(cx) {
    const live = [...this.state.values()].filter((current) => current.state === "live").length;
    if (this.space && live !== this.reported) {
      this.reported = live;
      setShared(LIVE, { ...shared(LIVE), [this.space]: live });
    }
    const asked = shared(CLOSE);
    if (!this.closing && this.space && asked?.space === this.space && asked.at > this.started) {
      this.closing = asked.tab;
      if (live) notify({ title: "Stopping the run config", body: `The Run tab closes when its ${live} processes have ended` });
      this.stop([...this.state.keys()], cx);
    }
    if (this.closing && !live && !this.gone) {
      this.gone = true;
      for (const address of this.meta.keys()) hc(["rm", address]);
      run("tab.close", { id: this.closing });
    }
  }

  async close() {
    for (const current of this.state.values()) if (current.state === "live") run("terminal.kill", { terminal: current.address });
    if (this.space) setShared(LIVE, { ...shared(LIVE), [this.space]: 0 });
  }

  favor(name, cx) {
    if (!this.favorites.delete(name)) this.favorites.add(name);
    this.pick({ favorites: [...this.favorites] });
    cx.notify();
  }

  config(name) {
    return this.configs.find((config) => config.name === name);
  }

  expand(value) {
    return (value ?? "").replaceAll("$PROJECT_DIR$", this.root).replaceAll("$USER_HOME$", home());
  }

  resolve(name, into = new Map(), skipped = []) {
    const config = this.config(name);
    if (!config || into.has(name)) return into;
    const option = (key) => this.expand(config.options?.[key]);
    if (config.type === "CompoundRunConfigurationType") {
      for (const child of [].concat(config.children ?? [])) this.resolve(child, into, skipped);
    } else if (config.type === "LaunchSettings") {
      const project = normalize(option("LAUNCH_PROFILE_PROJECT_FILE_PATH"));
      into.set(name, { name, project, cwd: parent(project),
        argv: ["dotnet", "run", "--no-build", "--project", project, "--launch-profile", option("LAUNCH_PROFILE_NAME")] });
    } else if (config.type === "RunNativeExe") {
      const exe = normalize(option("EXE_PATH")), args = words(option("PROGRAM_PARAMETERS"));
      into.set(name, { name, cwd: normalize(option("WORKING_DIRECTORY")) || this.root,
        argv: /\.(cmd|bat)$/i.test(exe) ? ["cmd.exe", "/d", "/c", exe, ...args] : [exe, ...args] });
    } else if (config.type === NPM) {
      into.set(name, { name, cwd: parent(normalize(option("package-json"))) || this.root,
        argv: ["cmd.exe", "/d", "/c", config.manager, option("command") || "run", ...[].concat(config.scripts ?? []), ...words(option("arguments"))] });
    } else skipped.push(name);
    return into;
  }

  processes() {
    const skipped = [], resolved = this.selected ? [...this.resolve(this.selected, new Map(), skipped).values()] : [];
    this.skipped = skipped;
    const known = new Set(resolved.map((process) => process.name));
    const others = [...this.state.keys()].filter((name) => name !== BUILD && !known.has(name) && this.live(name))
      .map((name) => [...this.resolve(name).values()][0] ?? { name, foreign: true });
    return [...resolved, ...others];
  }

  live(name) {
    return this.state.get(name)?.state === "live";
  }

  label() {
    return `runcfg.dir=${this.root.toLowerCase()}`;
  }

  async sync() {
    const listed = await hc(["ls", "--all", "--json", "--label", this.label()]);
    if (listed.code) return false;
    const state = new Map();
    let terminals = JSON.parse(listed.stdout).terminals ?? [];
    if (!this.cleaned) {
      this.cleaned = true;
      for (const terminal of terminals.filter((terminal) => terminal.state !== "live")) await hc(["rm", terminal.address]);
      terminals = terminals.filter((terminal) => terminal.state === "live");
    }
    for (const terminal of terminals) {
      if (!this.meta.has(terminal.address)) {
        const got = await hc(["get", terminal.address, "--json"]);
        if (got.code) continue;
        const facts = JSON.parse(got.stdout);
        this.meta.set(terminal.address, { name: facts.labels?.["runcfg.name"], created: facts.created_ms });
      }
      const { name, created } = this.meta.get(terminal.address);
      if (name && (state.get(name)?.created ?? 0) < created) {
        state.set(name, { address: terminal.address, state: terminal.state, exit: terminal.reason === "killed" ? 0 : terminal.exit_code, created });
      }
    }
    const before = JSON.stringify([...this.state]);
    this.state = state;
    return before !== JSON.stringify([...state]);
  }

  async read(name) {
    const current = this.state.get(name);
    if (!current || this.finalRead.has(current.address)) return false;
    const result = await hc(["read", current.address, "--lines", String(TAIL)]);
    if (result.code) return false;
    if (current.state !== "live") this.finalRead.add(current.address);
    const lines = tail(result.stdout), before = this.output.get(name);
    if (before && before.length === lines.length && before.every((line, index) => line === lines[index])) return false;
    this.output.set(name, lines);
    return true;
  }

  async launch(process) {
    const previous = this.state.get(process.name);
    if (previous?.state === "live") return null;
    if (previous) await hc(["rm", previous.address]);
    if (this.scrolled === process.name) this.scrolled = null;
    const started = await hc(["run", "--bg", "--json", "--no-parent", "--no-notify", "--cwd", process.cwd,
      "--label", this.label(), "--label", `runcfg.name=${process.name}`, "--", ...process.argv]);
    if (started.code) {
      notify({ title: `Could not start ${process.name}`, body: started.stderr.trim().split("\n")[0], level: "error" });
      return null;
    }
    this.output.delete(process.name);
    return JSON.parse(started.stdout).address;
  }

  buildProcess(projects) {
    const script = `foreach ($project in @(${projects.map(quote).join(", ")})) { `
      + "Write-Host \"Building $(Split-Path $project -Leaf)\"; & dotnet build $project --nologo -v q -clp:ErrorsOnly; "
      + "if ($LASTEXITCODE) { exit $LASTEXITCODE } }; Write-Host 'Build succeeded'";
    return { name: BUILD, cwd: this.root, argv: ["powershell.exe", "-NoProfile", "-Command", script] };
  }

  async advance() {
    const job = this.job;
    if (!job) return;
    const wanted = this.processes().filter((process) => job.names.includes(process.name) && !process.foreign);
    if (job.phase === "stopping") {
      const running = [...job.names, BUILD].filter((name) => this.live(name));
      for (const name of running.filter((name) => !job.killed.has(name))) {
        job.killed.add(name);
        await hc(["kill", this.state.get(name).address]);
      }
      if (running.length) return;
      const projects = [...new Set(wanted.map((process) => process.project).filter(Boolean))];
      if (!projects.length) job.phase = "starting";
      else {
        job.build = await this.launch(this.buildProcess(projects));
        job.phase = job.build ? "building" : null;
        this.open.add(BUILD);
      }
    } else if (job.phase === "building") {
      const build = this.state.get(BUILD);
      if (build?.address !== job.build || build.state === "live") return;
      if (build.exit) {
        notify({ title: "Build failed", body: `${this.selected}: nothing was started`, level: "error" });
        job.phase = null;
      } else {
        job.phase = "starting";
        this.open.delete(BUILD);
      }
    }
    if (job.phase === "starting") {
      for (const process of wanted) await this.launch(process);
      job.phase = null;
    }
    if (!job.phase && this.job === job) this.job = null;
  }

  tick(cx) {
    if (this.busy || !this.root) return;
    this.busy = true;
    cx.spawn(async (cx) => {
      try {
        const phase = this.job?.phase;
        let changed = await this.sync();
        this.leave(cx);
        await this.advance();
        if (this.job?.phase !== phase) changed = (await this.sync()) || true;
        const names = [BUILD, ...this.processes().map((process) => process.name)].filter((name) => this.state.has(name));
        const closed = names.filter((name) => !this.open.has(name));
        const peeked = closed.length ? [closed[this.turn++ % closed.length]] : [];
        for (const name of [...names.filter((name) => this.open.has(name)), ...peeked]) changed = (await this.read(name)) || changed;
        if (changed) cx.notify();
      } catch (error) {
        console.error(String(error?.message ?? error));
      }
      this.busy = false;
    });
  }

  begin(names, cx) {
    if (this.closing) return;
    this.job = { phase: "stopping", names, killed: new Set() };
    cx.notify();
  }

  stop(names, cx) {
    this.job = null;
    cx.spawn(async (cx) => {
      for (const name of names.filter((name) => this.live(name))) await hc(["kill", this.state.get(name).address]);
      cx.notify();
    });
  }

  select(name, cx) {
    this.selected = name;
    this.picking = false;
    this.pick({ selected: name });
    cx.notify();
  }

  type(name, cx) {
    if (!this.inputs.has(name)) {
      const input = InputState.new({ placeholder: "Enter sends this to the process" });
      input.on("submit", (_event, cx) => this.send(name, cx));
      this.inputs.set(name, input);
    }
    this.open.add(name);
    localStorage.setItem("open", JSON.stringify([...this.open]));
    this.inputs.get(name).focus();
    cx.timer.after(100, () => this.inputs.get(name).focus());
    cx.notify();
  }

  send(name, cx) {
    const current = this.state.get(name), input = this.inputs.get(name), text = input.value();
    if (current?.state !== "live") return;
    input.set_value("");
    cx.spawn(async () => {
      const sent = await hc(["send", current.address, "--", text]);
      if (sent.code) notify({ title: `Could not type into ${name}`, body: sent.stderr.trim().split("\n")[0], level: "error" });
    });
  }

  scrollBack(name, count, cx) {
    this.scrolled = name;
    this.scroll.scroll_to_item(count - 1);
    cx.notify();
  }

  follow(cx) {
    this.scrolled = null;
    cx.notify();
  }

  toggle(name, cx) {
    if (!this.open.delete(name)) this.open.add(name);
    else if (this.scrolled === name) this.scrolled = null;
    localStorage.setItem("open", JSON.stringify([...this.open]));
    cx.notify();
  }

  button(t, id, label, tip, action, enabled = true) {
    return h_flex().id(id).flex_none().h(22).px(7).gap(5).items_center().rounded(4)
      .text_color(enabled ? t.muted : t.border)
      .when(enabled, (el) => el.cursor_pointer().hover((s) => s.bg(t.raised).text_color(t.foreground)))
      .tooltip(tip)
      .on_click((_event, cx) => { cx.stop_propagation(); if (enabled) action(cx); })
      .child(label);
  }

  toolbar(t, list) {
    const names = list.filter((process) => !process.foreign).map((process) => process.name);
    const running = list.filter((process) => this.live(process.name)).length;
    const idle = names.filter((name) => !this.live(name));
    const busy = Boolean(this.job);
    return h_flex().h(BAR).flex_none().px(8).gap(6).items_center().bg(t.chrome).border_b(1).border_color(t.border)
      .child(h_flex().id("run-pick").flex_none().max_w(320).h(24).px(8).gap(6).items_center().rounded(5).cursor_pointer()
        .bg(t.raised).hover((s) => s.bg(t.hover))
        .tooltip(this.root ?? this.folder)
        .on_click((_event, cx) => { this.picking = !this.picking; cx.notify(); })
        .child(div().min_w(0).truncate().font_semibold().child(this.selected ?? "Pick a run config"))
        .child(div().flex_none().text_color(t.dim).child(this.picking ? "▴" : "▾")))
      .when(Boolean(this.selected), (el) => el
        .child(div().flex_none().text_color(running ? t.ansi2 : t.dim).child(`${running}/${list.length} running`)))
      .when(busy, (el) => el.child(div().flex_none().w(12).text_color(t.working).frames(SPIN, 90).child(SPIN[0]))
        .child(div().flex_none().text_color(t.dim).child(this.job.phase)))
      .child(div().flex_1())
      .child(this.button(t, "run-all", "▶ Run", "Start what is not running", (cx) => this.begin(idle, cx), !busy && Boolean(idle.length)))
      .child(this.button(t, "restart-all", "⟳ Restart all", "Stop, build and start everything", (cx) => this.begin(names, cx), !busy && Boolean(names.length)))
      .child(this.button(t, "stop-all", "■ Stop all", "Stop every process", (cx) => this.stop([BUILD, ...list.map((process) => process.name)], cx), busy || Boolean(running)))
      .child(this.button(t, "reload", "↻", "Read the .run folder again", (cx) => this.reload(cx)))
      .child(this.button(t, "shell", ">_ Terminal", "Open a terminal in this folder, under the run configs",
        () => run("terminal.open", { folder: this.root ?? this.folder, place: "down" })));
  }

  picker(t) {
    const groups = this.configs.filter((config) => config.type === "CompoundRunConfigurationType");
    const singles = this.configs.filter((config) => config.type !== "CompoundRunConfigurationType");
    const favorite = (config) => this.favorites.has(config.name);
    const top = [...groups, ...singles].filter(favorite), rest = [...groups, ...singles].filter((config) => !favorite(config));
    const row = (config) => h_flex().id(`pick-${config.name}`).h(ROW).flex_none().pl(5).pr(12).gap(6).items_center().cursor_pointer()
      .when(config.name === this.selected, (el) => el.bg(t.selected))
      .hover((s) => s.bg(t.hover))
      .on_click((_event, cx) => this.select(config.name, cx))
      .child(this.button(t, `favor-${config.name}`, div().when(favorite(config), (el) => el.text_color(t.ansi3)).child(favorite(config) ? "★" : "☆"),
        favorite(config) ? "Remove from favorites" : "Add to favorites", (cx) => this.favor(config.name, cx)))
      .child(div().flex_none().w(44).text_size(11).text_color(t.dim).child(TYPES[config.type] ?? "other"))
      .child(div().min_w(0).truncate().text_color(TYPES[config.type] ? t.foreground : t.dim).child(config.name))
      .when(config.type === "CompoundRunConfigurationType", (el) => el
        .child(div().flex_none().text_color(t.dim).child(`${this.resolve(config.name).size} processes`)));
    return v_flex().id("run-picker").flex_1().min_h(0).overflow_y_scrollbar().py(4)
      .children([...top.map(row), ...(top.length && rest.length ? [div().flex_none().h(1).mx(12).my(4).bg(t.border)] : []), ...rest.map(row)])
      .when(!this.configs.length, (el) => el.child(div().px(12).py(8).text_color(t.dim).child("No run configurations found")));
  }

  status(t, name) {
    const current = this.state.get(name), queued = this.job?.names.includes(name) || (name === BUILD && this.job?.phase === "building");
    if (current?.state === "live") return { color: t.ansi2, glyph: "●", text: "running" };
    if (queued) return { color: t.working, glyph: SPIN[0], spin: true, text: this.job.phase };
    if (!current) return { color: t.border, glyph: "○", text: "not started" };
    return current.exit ? { color: t.ansi1, glyph: "●", text: `exit ${current.exit}` } : { color: t.dim, glyph: "○", text: "stopped" };
  }

  lineColor(t, line) {
    const text = line.replace(/\b(0|no) (errors?|warnings?|failures?|failed)\b/gi, "");
    if (/\b(ERR|FTL|CRIT)\b|\b(error|fail|exception)/i.test(text)) return t.ansi1;
    if (/\bWRN\b|\bwarn/i.test(text)) return t.ansi3;
    if (/\b(DBG|VRB)\b|^(dbug|trce):/.test(text)) return t.dim;
    return SUCCESS.test(text) ? t.ansi2 : t.muted;
  }

  segments(t, line) {
    const base = this.lineColor(t, line), parts = [];
    const levels = { INF: t.ansi2, info: t.ansi2, DBG: t.dim, VRB: t.dim, dbug: t.dim, trce: t.dim, WRN: t.ansi3, warn: t.ansi3,
      ERR: t.ansi1, FTL: t.ansi1, CRIT: t.ansi1, fail: t.ansi1, crit: t.ansi1 };
    let at = 0;
    for (const match of line.matchAll(MARKS)) {
      if (match.index > at) parts.push([line.slice(at, match.index), base]);
      parts.push([match[0], match[1] ? t.ansi4 : match[2] ? t.dim : levels[match[3] ?? match[4]], match[1] && link(match[1])]);
      at = match.index + match[0].length;
    }
    if (at < line.length) parts.push([line.slice(at), base]);
    return parts.length ? parts : [[" ", base]];
  }

  section(t, process) {
    const name = process.name, open = this.open.has(name), current = this.state.get(name), status = this.status(t, name);
    const lines = this.output.get(name) ?? [], live = current?.state === "live", last = lines[lines.length - 1];
    const startable = !process.foreign && name !== BUILD && !this.job;
    const header = h_flex().id(`row-${name}`).h(ROW).flex_none().px(8).gap(8).items_center().cursor_pointer()
      .border_b(1).border_color(t.border).hover((s) => s.bg(t.hover))
      .on_click((_event, cx) => this.toggle(name, cx))
      .child(div().flex_none().w(10).text_color(t.dim).child(open ? "▾" : "▸"))
      .child(div().flex_none().w(12).text_color(status.color).when(Boolean(status.spin), (el) => el.frames(SPIN, 90)).child(status.glyph))
      .child(div().flex_none().w(NAME).truncate().font_semibold().child(name))
      .child(div().flex_1().min_w(0).truncate().text_color(open || !last ? t.dim : this.lineColor(t, last))
        .when(!open && Boolean(last), (el) => el.font_family(settings().font_family ?? "JetBrains Mono").text_size(11))
        .child(open || !last ? status.text : last))
      .when(open && this.scrolled === name, (el) => el.child(this.button(t, `follow-${name}`, "↓ Follow", "Show new output as it comes again", (cx) => this.follow(cx))))
      .when(startable, (el) => el.child(this.button(t, `start-${name}`, live ? "⟳" : "▶", live ? "Restart (builds first)" : "Start (builds first)", (cx) => this.begin([name], cx))))
      .when(live, (el) => el
        .child(this.button(t, `stop-${name}`, "■", "Stop", (cx) => this.stop([name], cx)))
        .child(this.button(t, `type-${name}`, "⌨", "Type into this process", (cx) => this.type(name, cx)))
        .child(this.button(t, `peek-${name}`, ">_", "Open the real terminal", () => run("terminal.peek", { terminal: current.address }))));
    if (!open) return [header];
    const typing = live && this.inputs.has(name) ? [h_flex().flex_none().h(ROW).px(10).gap(6).items_center().bg(t.surface).border_b(1).border_color(t.border)
      .child(div().flex_none().text_color(t.dim).child("›"))
      .child(Input.new(this.inputs.get(name)).flex_1().h_full().text_size(11).text_color(t.foreground))] : [];
    const scrolling = this.scrolled === name, shown = scrolling ? lines : lines.slice(-SHOWN);
    const rows = shown.map((line, row) => h_flex().flex_none().whitespace_nowrap()
      .children(this.segments(t, line).map(([text, color, url], index) => url
        ? div().id(`link-${name}-${row}-${index}`).flex_none().text_color(color).text_decoration_1().cursor_pointer()
          .hover((s) => s.text_color(t.foreground))
          .on_click((_event, cx) => { cx.stop_propagation(); exec("explorer.exe", [url]); })
          .child(text)
        : div().flex_none().text_color(color).child(text))));
    const empty = div().flex_none().text_color(t.dim).child(current ? "No output yet" : "Not started");
    const output = scrolling
      ? v_flex().id(`out-${name}`).size_full().px(10).py(4).overflow_y_scrollbar().track_scroll(this.scroll).children(rows)
      : v_flex().size_full().px(10).py(4).justify_end().children(rows.length ? rows : [empty]);
    return [header, div().id(`box-${name}`).flex_1().min_h(48).overflow_hidden().bg(t.surface).border_b(1).border_color(t.border)
      .font_family(settings().font_family ?? "JetBrains Mono").text_size(11)
      .when(!scrolling, (el) => el.on_scroll_wheel((event, cx) => { if (event.delta.y > 0 && lines.length) this.scrollBack(name, lines.length, cx); }))
      .child(output), ...typing];
  }

  render() {
    const t = theme();
    const list = this.root ? this.processes() : [];
    const rows = this.state.has(BUILD) || this.job?.phase === "building" ? [{ name: BUILD }, ...list] : list;
    return v_flex().id("run-configs").size_full().min_h(0).overflow_hidden().bg(t.background).text_color(t.foreground).text_size(12)
      .child(this.toolbar(t, list))
      .when(Boolean(this.closing), (el) => el.child(div().flex_none().px(12).py(6).bg(t.raised).text_color(t.working)
        .child("Stopping every process. This tab closes when they have ended; close it again to not wait.")))
      .when(Boolean(this.error), (el) => el.child(div().px(12).py(8).text_color(t.ansi1).child(this.error)))
      .when(!this.error && (this.picking || !this.selected), (el) => el.child(this.picker(t)))
      .when(!this.error && !this.picking && Boolean(this.selected), (el) => el
        .child(v_flex().flex_1().min_h(0).overflow_hidden().children(rows.flatMap((process) => this.section(t, process))))
        .when(Boolean(this.skipped.length), (el) => el
          .child(div().flex_none().px(10).py(4).text_color(t.dim).child(`Not supported, skipped: ${this.skipped.join(", ")}`))));
  }
}
