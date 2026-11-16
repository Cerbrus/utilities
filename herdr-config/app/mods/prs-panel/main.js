import { View, div } from "gpui-kit";
import { v_flex, h_flex, Scrollbar } from "gpui-base";
import { exec, theme, run, layout, props, checking, spaces, agents, panes, notify } from "herdr";

const OWNER = "Baseflow";
const REPOS = /^(asito|mtp)-/;
const BAR = 28, SEAM = 1, ROW = 24, MAX_ROWS = 8;
const REFRESH_MS = 5 * 60 * 1000, TICK_MS = 60 * 1000;
const ROOTS = ["C:\DEV", "C:\DEV\~Cerbrus"];
const ARGV = ["claude"];
const AGENT_WAIT_MS = 90 * 1000;
const reviewText = (item) => `Review #${item.number}`;
const URGENCY = ["red", "yellow", "green", "draft", "waiting"];
const FLAG_GLYPHS = { red: "●", yellow: "●", green: "●", draft: "✎", waiting: "○" };
const REVIEW_GLYPHS = { REQUESTED: "◷", APPROVED: "✓", CHANGES_REQUESTED: "✗", COMMENTED: "…" };
const REVIEW_WORDS = { REQUESTED: "requested", APPROVED: "approved", CHANGES_REQUESTED: "changes requested", COMMENTED: "commented" };

const PERSON = "login ... on User { name }";
const QUERY = `query($mine: String!, $requested: String!, $reviewed: String!) {
  viewer { login }
  mine: search(query: $mine, type: ISSUE, first: 50) { nodes { ...pr } }
  requested: search(query: $requested, type: ISSUE, first: 50) { nodes { ...pr } }
  reviewed: search(query: $reviewed, type: ISSUE, first: 50) { nodes { ...pr } }
}
fragment pr on PullRequest {
  url number title isDraft updatedAt mergeable reviewDecision
  repository { name }
  author { login }
  labels(first: 20) { nodes { name } }
  reviewRequests(first: 20) { nodes { requestedReviewer { ... on User { login name } ... on Bot { login } } } }
  latestReviews(first: 20) { nodes { state author { ${PERSON} } } }
  reviews(first: 100) { nodes { state submittedAt author { ${PERSON} } } }
}`.replace(/\s+/g, " ");

const find = (node, id) => !node ? null : node.id === id ? node : (node.children ?? []).map((child) => find(child, id)).find(Boolean) ?? null;
const human = (person) => !/copilot/i.test(person?.login ?? "copilot");
const folderName = (path) => (path ?? "").replace(/[\/]+$/, "").split(/[\/]/).pop().toLowerCase();
const firstName = (person) => person.name?.split(" ")[0] || person.login;

function age(iso, now) {
  const minutes = Math.max(0, Math.floor((now - Date.parse(iso)) / 60000));
  if (minutes < 60) return `${minutes}m`;
  return minutes < 1440 ? `${Math.floor(minutes / 60)}h` : `${Math.floor(minutes / 1440)}d`;
}

function facts(node) {
  const requests = node.reviewRequests.nodes.map((request) => request.requestedReviewer).filter(human);
  const submitted = (review) => review.state !== "PENDING" && human(review.author);
  const latest = node.latestReviews.nodes.filter(submitted);
  const last = new Map();
  for (const review of node.reviews.nodes.filter(submitted).sort((a, b) => (a.submittedAt ?? "").localeCompare(b.submittedAt ?? ""))) {
    if (review.state !== "COMMENTED") last.set(review.author.login, review);
  }
  const standing = [...last.values()].filter((review) => review.state === "APPROVED" || review.state === "CHANGES_REQUESTED").map((review) => review.author);
  const reviewers = [
    ...requests.map((person) => ({ login: person.login, name: firstName(person), state: "REQUESTED" })),
    ...latest.filter((review) => REVIEW_GLYPHS[review.state] && !requests.some((person) => person.login === review.author.login))
      .map((review) => ({ login: review.author.login, name: firstName(review.author), state: review.state })),
  ];
  return { requests, latest, standing, reviewers };
}

function authoredAction(node, { requests, latest }) {
  const has = (state) => latest.some((review) => review.state === state);
  if (node.mergeable === "CONFLICTING") return ["red", "Resolve conflicts"];
  if (node.reviewDecision === "CHANGES_REQUESTED" && has("CHANGES_REQUESTED")) return ["red", "Address changes"];
  if (node.reviewDecision === "APPROVED") return ["green", "Merge it"];
  if (node.isDraft) return ["draft", "Draft, mark ready"];
  if (node.labels.nodes.some((label) => label.name === "ship")) return ["waiting", "Ship, awaiting merge"];
  if (!requests.length && !latest.length) return ["yellow", "Add reviewers"];
  if (has("COMMENTED")) return ["yellow", "Address comments"];
  return ["waiting", "Waiting on review"];
}

function reviewAction(me, { requests, latest, standing }) {
  const mine = latest.find((review) => review.author.login === me)?.state;
  const others = standing.filter((person) => person.login !== me).map(firstName);
  if (mine && !requests.some((person) => person.login === me)) return ["green", "Done, author's turn"];
  if (others.length && mine !== "CHANGES_REQUESTED") return ["yellow", `Reviewed by ${others.join(", ")}`];
  return ["red", "Review needed"];
}

function entry(node, kind, me) {
  const found = facts(node);
  const [flag, action] = kind === "mine" ? authoredAction(node, found) : reviewAction(me, found);
  return { kind, id: `${kind}-${node.repository.name}-${node.number}`, url: node.url, label: `${node.repository.name.replace(REPOS, "")}#${node.number}`,
    repo: node.repository.name, number: node.number, title: node.title, updated: node.updatedAt, flag, action, reviewers: found.reviewers };
}

function overview(data) {
  const me = data.viewer.login, scoped = (nodes) => nodes.filter((node) => node?.repository && REPOS.test(node.repository.name));
  const order = (entries) => entries.sort((a, b) => URGENCY.indexOf(a.flag) - URGENCY.indexOf(b.flag) || b.updated.localeCompare(a.updated));
  const seen = new Set();
  const incoming = scoped([...data.requested.nodes, ...data.reviewed.nodes]).filter((node) => node.author?.login !== me && !seen.has(node.url) && seen.add(node.url));
  return { mine: order(scoped(data.mine.nodes).map((node) => entry(node, "mine", me))), review: order(incoming.map((node) => entry(node, "review", me))) };
}

export default class PullRequests extends View {
  init(_props, cx) {
    this.block = props()?.block ?? "prs";
    this.mine = [];
    this.review = [];
    this.loading = false;
    if (checking()) return;
    cx.timer.every(TICK_MS, (cx) => { if (Date.now() - (this.started ?? 0) >= REFRESH_MS) this.refresh(cx); else cx.notify(); });
    this.refresh(cx);
  }

  refresh(cx) {
    if (this.loading) return;
    this.loading = true;
    this.started = Date.now();
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        const search = (filter) => `org:${OWNER} is:pr is:open ${filter}`;
        const result = await exec("gh", ["api", "graphql", "-f", `query=${QUERY}`, "-f", `mine=${search("author:@me")}`,
          "-f", `requested=${search("review-requested:@me")}`, "-f", `reviewed=${search("reviewed-by:@me")}`], { timeout: 60000 });
        if (result.code) throw new Error(result.stderr.trim().split("\n")[0] || `gh exited with ${result.code}`);
        Object.assign(this, overview(JSON.parse(result.stdout).data));
        this.loaded = Date.now();
        this.error = null;
      } catch (error) {
        this.error = String(error?.message ?? error);
      }
      this.loading = false;
      cx.notify();
    });
  }

  collapsed() {
    return (find(layout(), this.block)?.size?.px ?? 0) <= BAR + SEAM;
  }

  toggle() {
    const px = find(layout(), this.block)?.size?.px ?? 0;
    if (px > BAR + SEAM) {
      localStorage.setItem("height", String(px));
      run("layout.resize", { id: this.block, px: BAR + SEAM });
      return;
    }
    const rows = Math.min(MAX_ROWS, Math.max(1, this.mine.length, this.review.length));
    run("layout.resize", { id: this.block, px: Number(localStorage.getItem("height")) || SEAM + BAR + SEAM + ROW + rows * ROW + 8 });
  }

  spaceFor(repo) {
    const name = repo.toLowerCase(), local = spaces().filter((space) => !space.machine);
    const tabs = new Set(panes().filter((pane) => folderName(pane.cwd) === name).map((pane) => pane.tab));
    return local.find((space) => space.name.toLowerCase() === name) ?? local.find((space) => space.tabs.some((tab) => tabs.has(tab.id)));
  }

  async folderFor(repo) {
    for (const root of ROOTS) {
      const folder = `${root}\${repo}`;
      const found = await exec("cmd", ["/c", "dir", "/b", "/ad", folder]).catch(() => null);
      if (found && !found.code) return folder;
    }
    return null;
  }

  startReview(item, cx) {
    const text = reviewText(item), space = this.spaceFor(item.repo);
    this.pending = { repo: item.repo, text, known: new Set(agents().map((agent) => agent.address)), until: Date.now() + AGENT_WAIT_MS };
    if (space) {
      run("space.select", { id: space.id });
      run("tab.new", { space: space.id, argv: ARGV });
      return this.awaitAgent(cx);
    }
    cx.spawn(async (cx) => {
      const folder = await this.folderFor(item.repo);
      if (!folder) {
        this.pending = null;
        notify({ title: `No folder for ${item.repo}`, body: `Looked in ${ROOTS.join(" and ")}`, level: "warning" });
        return;
      }
      run("space.new", { folder, argv: ARGV });
      this.awaitAgent(cx);
    });
  }

  awaitAgent(cx) {
    cx.timer.after(500, (cx) => {
      const pending = this.pending;
      if (!pending) return;
      const space = this.spaceFor(pending.repo);
      const agent = space && agents().find((candidate) => candidate.space === space.id && !pending.known.has(candidate.address) && candidate.status === "idle");
      if (agent) {
        this.pending = null;
        this.deliver(agent, pending.text, cx);
      } else if (Date.now() > pending.until) {
        this.pending = null;
        notify({ title: `No agent came up in ${pending.repo}`, body: `"${pending.text}" was not typed`, level: "warning" });
      } else this.awaitAgent(cx);
    });
  }

  deliver(agent, text, cx) {
    run("space.select", { id: agent.space });
    run("tab.select", { id: agent.tab });
    run("pane.focus", { terminal: agent.address });
    const previous = cx.read_from_clipboard();
    cx.write_to_clipboard(text);
    cx.timer.after(200, () => run("terminal.paste"));
    cx.timer.after(1500, (cx) => { if (previous !== undefined) cx.write_to_clipboard(previous); });
  }

  colors(t) {
    return { red: t.ansi1, yellow: t.ansi3, green: t.ansi2, draft: t.muted, waiting: t.dim };
  }

  counts(t) {
    const colors = this.colors(t), all = [...this.mine, ...this.review];
    return URGENCY.map((flag) => [flag, all.filter((item) => item.flag === flag).length]).filter(([, count]) => count)
      .map(([flag, count]) => h_flex().flex_none().gap(3).items_center()
        .child(div().text_color(colors[flag]).child(FLAG_GLYPHS[flag]))
        .child(div().text_color(t.muted).child(String(count))));
  }

  bar(t, collapsed) {
    const colors = this.colors(t), all = [...this.mine, ...this.review];
    const top = ["red", "yellow", "green"].map((flag) => all.find((item) => item.flag === flag)).find(Boolean);
    const status = this.error ? "failed" : this.loaded ? age(new Date(this.loaded).toISOString(), Date.now()) : "";
    return h_flex().id("prs-bar").h(BAR).flex_none().px(12).gap(10).items_center().cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .on_click(() => this.toggle())
      .child(div().flex_none().w(10).text_color(t.dim).child(collapsed ? "▸" : "▾"))
      .child(div().flex_none().font_semibold().child("PRs"))
      .child(h_flex().flex_none().gap(8).items_center().children(this.counts(t)))
      .when(!this.loaded && !this.error, (el) => el.child(div().text_color(t.dim).child("Loading")))
      .when(Boolean(this.loaded) && !all.length, (el) => el.child(div().text_color(t.dim).child("No open pull requests")))
      .when(Boolean(this.error), (el) => el.child(div().flex_1().min_w(0).truncate().text_color(t.ansi1).child(this.error)))
      .when(collapsed && !this.error && Boolean(top), (el) => el
        .child(div().flex_none().text_color(t.dim).child("·"))
        .child(h_flex().id("prs-top").flex_1().min_w(0).gap(6).items_center()
          .on_click((_e, cx) => { cx.stop_propagation(); cx.open_url(top.url); })
          .child(div().flex_none().text_color(colors[top.flag]).child(top.label))
          .child(div().min_w(0).truncate().text_color(t.muted).child(top.action))))
      .child(div().flex_1())
      .child(h_flex().id("prs-refresh").flex_none().h(20).px(6).gap(5).items_center().rounded(4).text_color(t.dim)
        .hover((s) => s.bg(t.raised).text_color(t.foreground))
        .tooltip(this.error ?? "Refresh now")
        .on_click((_e, cx) => { cx.stop_propagation(); this.refresh(cx); })
        .child(this.loading ? div().w(10).frames(["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"], 90) : div().w(10).child("⟳"))
        .child(div().child(status)));
  }

  row(item, t, now) {
    const colors = this.colors(t);
    const reviewColors = { REQUESTED: t.dim, APPROVED: t.ansi2, CHANGES_REQUESTED: t.ansi1, COMMENTED: t.ansi3 };
    const people = item.reviewers.map((person) => `${person.name} ${REVIEW_WORDS[person.state]}`).join(", ");
    return h_flex().id(`pr-${item.id}`).h(ROW).flex_none().px(10).gap(8).items_center().cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .tooltip([item.action, `${item.repo}#${item.number}`, people].filter(Boolean).join("\n"))
      .on_click((_e, cx) => cx.open_url(item.url))
      .child(div().flex_none().w(12).text_color(colors[item.flag]).child(FLAG_GLYPHS[item.flag]))
      .child(item.kind === "review"
        ? div().id(`review-${item.id}`).flex_none().w(138).truncate().text_color(t.foreground)
          .hover((s) => s.text_color(t.accent))
          .on_click((_e, cx) => { cx.stop_propagation(); this.startReview(item, cx); })
          .child(item.label)
        : div().flex_none().w(138).truncate().text_color(t.foreground).child(item.label))
      .child(div().flex_1().min_w(0).truncate().text_color(t.muted).child(item.title))
      .child(h_flex().flex_none().gap(3).children(item.reviewers.map((person) => div().text_color(reviewColors[person.state]).child(REVIEW_GLYPHS[person.state]))))
      .child(div().flex_none().w(28).flex().justify_end().text_color(t.dim).child(age(item.updated, now)));
  }

  column(key, title, items, t, now) {
    const empty = this.loaded ? "Nothing here" : "";
    return v_flex().flex_1().h_full().min_w(0).min_h(0)
      .child(h_flex().h(ROW).flex_none().px(10).gap(6).items_center().text_size(11)
        .child(div().font_semibold().text_color(t.dim).child(title))
        .child(div().text_color(t.dim).child(`(${items.length})`)))
      .child(div().flex_1().min_h(0).relative()
        .child(v_flex().id(`prs-${key}`).absolute().inset_0().overflow_y_scroll().children(items.map((item) => this.row(item, t, now)))
          .when(!items.length, (el) => el.child(div().px(10).h(ROW).flex().items_center().text_color(t.dim).child(empty))))
        .child(Scrollbar.vertical(`prs-${key}`).absolute().inset_0()));
  }

  render() {
    const t = theme(), collapsed = this.collapsed(), now = Date.now();
    return v_flex().id("prs").size_full().min_h(0).overflow_hidden().bg(t.background).text_color(t.foreground).text_size(12)
      .child(div().h(SEAM).flex_none().bg(t.border))
      .child(this.bar(t, collapsed))
      .when(!collapsed, (el) => el
        .child(div().h(SEAM).flex_none().bg(t.border))
        .child(div().flex().flex_1().min_h(0)
          .child(this.column("review", "TO REVIEW", this.review, t, now))
          .child(div().w(1).h_full().flex_none().bg(t.border))
          .child(this.column("mine", "MINE", this.mine, t, now))));
  }
}
