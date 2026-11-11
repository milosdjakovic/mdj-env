// Agents in grouped or priority views; parents take their most urgent sub-agent's place.
// A viewed done agent stays in Done until left.

import { View, div, image, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { agents, terminals, panes, focused, spaces, run, theme, shared, setShared, setAgentOrder, openOverlay, closeOverlay, props, window, layout, settings } from "herdr";

// mdj: Spaces and Agents share one split. The layout's own boundary drag jumped about under the
// grip, so the lists drag it themselves. Each list hears the pointer only while it is over that
// list, so the drag lives in shared state where both can see it, and leaving both lists ends it.
// The pointer and the measured height are in window points; layout px are before the zoom.
const SPLIT = "mdj.split";
function splitDrag(el, me) {
  return el
    .on_mouse_move((e) => {
      const s = shared(SPLIT);
      if (!s) return;
      const px = Math.max(90, Math.round((s.h + e.position.y - s.y) / (settings().zoom ?? 1)));
      if (px !== s.px) { setShared(SPLIT, { ...s, px }); run("layout.resize", { id: "spaces", px }); }
    })
    .on_mouse_up("left", () => { if (shared(SPLIT)) setShared(SPLIT, null); })
    .on_hover((hovered, cx) => {
      setShared(`${SPLIT}.over.${me}`, hovered);
      if (!hovered && shared(SPLIT)) cx.timer.after(150, () => {
        if (!shared(`${SPLIT}.over.spaces`) && !shared(`${SPLIT}.over.agents`)) setShared(SPLIT, null);
      });
    });
}

// mdj: a list that can scroll further fades into the canvas at that edge. The list is not a scroll area,
// so the wheel moves its own offset, which drawnAt keeps inside what the content leaves.
function scrolled(view, e) {
  const max = Math.max(0, (view.contentH ?? 0) - (view.viewH ?? 0));
  view.off = Math.min(max, Math.max(0, (view.off ?? 0) - e.delta.y));
}
// The offset the list is drawn at, in layout px: kept inside what the content leaves (in window points,
// as sizes are reported) and divided by the zoom, since a position is set before the zoom.
function drawnAt(view) {
  const max = Math.max(0, (view.contentH ?? 0) - (view.viewH ?? 0));
  view.off = Math.min(max, Math.max(0, view.off ?? 0));
  return view.off / (settings().zoom ?? 1);
}
// The panel stops a few points short of its block and its rows draw on into that strip, which
// clipping does not catch, so the bottom band runs past the panel; the next block covers the rest.
function fades(t, view, inset) {
  const max = (view.contentH ?? 0) - (view.viewH ?? 0);
  if (max <= 1) return [];
  // A long, eased band in 1px steps, up to a third of the list, so the edge melts rather than cuts.
  const n = Math.max(8, Math.min(36, Math.round((view.viewH ?? 0) / 3)));
  const band = (top) => v_flex().absolute().left(0).right(0).h(n).when(top, el => el.top(inset)).when(!top, el => el.bottom(-10))
    .children(Array.from({ length: n }, (_, i) => {
      // x is the distance from the list's edge, 0 at the edge and 1 at the band's inner end.
      const x = ((top ? i : n - 1 - i) + 0.5) / n, ease = 1 - x * x * (3 - 2 * x);
      const a = Math.round(235 * ease);
      return div().h(1).w_full().flex_none().bg(t.canvas + a.toString(16).padStart(2, "0"));
    }));
  const out = [];
  if ((view.off ?? 0) > 1) out.push(band(true));
  if ((view.off ?? 0) < max - 1) out.push(band(false));
  return out;
}

// mdj: the selected look, the pane's own background and a soft shadow, is a layer under the row's content.
// Selecting shows it at once; a fade on switching was tried and taken out, asked for on 2026-11-09.
// A hovered row that is not selected gets the same colour at half strength and no shadow, so it never looks selected.
const card = (id, on, t, radius = 7) => div().id(id).absolute().top(0).left(0).right(0).bottom(0).rounded(radius)
  .bg(t.background).shadow_sm().opacity(on ? 1 : 0);
const dimmed = (t) => t.background + "80";

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// The sidebar's rail goes by its width, not a flag: dragging its edge narrows it too.
const narrow = () => (find(layout(), "sidebar")?.size?.px ?? Infinity) < 160;

const clean = (s) => (s ?? "").replace(/^[^\p{L}\p{N}]+/u, "").trim();

function leadPanes(all) {
  const leads = new Map();
  for (const p of all) {
    if (!p.terminal) continue;
    const current = leads.get(p.tab);
    // First agent, else first focused terminal, else first terminal in the tab.
    if (!current || (!current.program?.agent && (p.program?.agent || (!current.focused && p.focused)))) leads.set(p.tab, p);
  }
  return leads;
}

function title(tab, l) {
  const prog = l?.program?.name;
  const live = clean(l?.title);
  const telling = live && live !== prog && !/^[~/]|^[A-Za-z]:\\/.test(live) && !live.includes("@") && live.toLowerCase() !== l?.program?.key;
  return (tab.name === prog || !tab.named) && telling ? live : tab.name;
}
const RANK = { blocked: 4, done: 3, working: 2, idle: 1 };
// A sub-agent without a pane isn't in agents(): its raw word, error counting as
// blocked. It's never done: it reports to its parent, and the parent's done is the news.
const kidStatus = (k, listed) => {
  const s = listed.get(k.address) ?? k.status;
  return s === "error" ? "blocked" : s === "done" ? "idle" : s;
};
const SORTS = [
  { id: "priority", label: "Priority", icon: "clock" },
  { id: "grouped", label: "Grouped by space", icon: "layers" },
];
const sortOf = () => SORTS.find((s) => s.id === shared("agents.sort")) ?? SORTS[0];
const SECTION = { 4: "Needs you", 3: "Done", 2: "Working", 1: "Idle" };
const SECTION_STATUS = { 4: "blocked", 3: "done", 2: "working" };

function duration(ms) {
  const m = Math.floor(ms / 60000);
  if (m < 1) return "<1m";
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  return h < 24 ? `${h}h` : `${Math.floor(h / 24)}d`;
}

// The agent's icon from the app's program table: a one-color glyph or a picture.
// mdj: the state a rail shows in one 18px slot: the spinner while working, a check when done, a ! when
// blocked, otherwise what the caller gives, an agent's program icon or nothing for a space.
function railState(t, status, rest) {
  const box = h_flex().size(18).flex_none().items_center().justify_center();
  if (status === "working") return box.child(svg("mods/workspace-chrome/spinner.svg").size(14).text_color(t.working).spin(900));
  if (status === "done") return box.child(svg("mods/workspace-chrome/check.svg").size(14).text_color(t.done ?? t.foreground));
  if (status === "blocked") return box.child(div().size(14).rounded(4).bg(t.blocked + "26").text_size(10.5).font_bold().text_color(t.blocked).flex().items_center().justify_center().child("!"));
  return rest ? box.child(rest) : box;
}

function icon(p, size, color) {
  if (!p?.icon) return null;
  return p.tint ? svg(p.icon).size(size).flex_none().text_color(color) : image(p.icon).w(size).h(size).flex_none();
}

export default class Agents extends View {
  init(_props, cx) {
    if (props()?.sortMenu) return;
    this.folded = new Set();
    // Each agent's last state and when it changed (ms), kept across restarts.
    this.changed = JSON.parse(localStorage.getItem("changed") ?? "{}");
    this.pendingPins = JSON.parse(localStorage.getItem("pins") ?? "[]");
    if (!this.pendingPins.length) localStorage.removeItem("pins");
    this.migratingPins = new Set();
    cx.timer.every(30000, (cx) => cx.notify());
  }

  // Stamps agents whose state changed. Done and idle count as one: looking at a
  // finished agent turns done into idle, and looking isn't the agent doing anything.
  track(list, now) {
    let dirty = false;
    for (const a of list) {
      const s = a.status === "done" ? "idle" : a.status;
      if (this.changed[a.address]?.s === s) continue;
      this.changed[a.address] = { s, at: now };
      dirty = true;
    }
    if (!dirty) return;
    // Gone and old: the list alone is empty right after a start.
    const listed = new Set(list.map((a) => a.address));
    for (const [k, c] of Object.entries(this.changed)) if (!listed.has(k) && now - c.at > 30 * 86400000) delete this.changed[k];
    localStorage.setItem("changed", JSON.stringify(this.changed));
  }

  // Keep offline pins until their terminal returns, and keep each pending until
  // core echoes the label so a failed write doesn't erase the old pin.
  migratePins(all) {
    const listed = new Map(all.filter((t) => t.state === "live").map((t) => [t.address, t]));
    const pending = this.pendingPins.filter((address) => {
      const terminal = listed.get(address);
      if (!terminal) return true;
      if (terminal.labels?.["herdr.pinned"]) return false;
      if (!this.migratingPins.has(address)) {
        this.migratingPins.add(address);
        run("terminal.pin", { terminal: address, pinned: true });
      }
      return true;
    });
    if (pending.length === this.pendingPins.length) return;
    this.pendingPins = pending;
    if (pending.length) localStorage.setItem("pins", JSON.stringify(pending));
    else localStorage.removeItem("pins");
  }

  since(a) {
    return this.changed[a.address]?.at ?? 0;
  }

  // Looking at a done agent makes it idle; it stays with Done until you leave
  // it rather than drop away under you. Any other change moves it at once.
  hold(list) {
    const cur = list.find((a) => a.focused);
    const same = cur && cur.address === this.held?.address;
    // Arriving, or any change but done turning idle, sets what it was.
    if (!same || cur.status !== "idle") this.held = cur ? { address: cur.address, rank: RANK[cur.status] ?? 0 } : null;
  }

  rank(a) {
    const sawDone = a.address === this.held?.address && this.held.rank === RANK.done && a.status === "idle";
    return sawDone ? RANK.done : RANK[a.status] ?? 0;
  }

  sortMenu(t) {
    const on = sortOf().id;
    return v_flex()
      .w_full()
      .p(5)
      .bg(t.popover)
      .text_size(12.8)
      .child(div().px(8).pt(4).pb(6).text_size(11).text_color(t.dim).child("Sort agents"))
      .children(SORTS.map((s) => h_flex()
        .id(`sort-${s.id}`)
        .h(31)
        .px(8)
        .gap(9)
        .rounded(7)
        .items_center()
        .text_color(t.foreground)
        .hover((el) => el.bg((t.hover === t.canvas ? t.chrome : t.hover)))
        .on_click(() => {
          setShared("agents.sort", s.id);
          closeOverlay(props().overlay);
        })
        .child(svg(`mods/workspace-chrome/${s.icon}.svg`).size(14).flex_none().text_color(t.muted))
        .child(div().flex_1().child(s.label))
        .when(s.id === on, (el) => el.child(svg("mods/workspace-chrome/check.svg").size(14).flex_none().text_color(t.foreground)))));
  }

  peek(addr) {
    run("terminal.peek", { terminal: addr });
  }

  // Live sub-agents of `addr`, depth first, each with the tree lines in front of it.
  tree(all, addr, lead = []) {
    const kids = all.filter((k) => k.parent === addr && k.state === "live");
    return kids.flatMap((k, i) => {
      const last = i === kids.length - 1;
      return [
        { t: k, lines: [...lead, last ? "└" : "├"] },
        ...this.tree(all, k.address, [...lead, last ? "" : "│"]),
      ];
    });
  }

  subRow(t, s, shown, compact, rail = false) {
    const k = s.t;
    const st = kidStatus(k, this.listed);
    const pic = icon(k.program, 14, t.foreground);
    const on = k.address === shown;
    const open = () => (this.listed.has(k.address) ? run("pane.focus", { terminal: k.address }) : this.peek(k.address));
    // mdj: on the rail a sub-agent is a cube like its parent's, in the same place its row has open.
    if (rail) return h_flex().id(`sub-${k.address}`).relative().w_full().h(28).flex_none().rounded(7).items_center().justify_center()
      .tooltip(String(k.name || k.template || k.program?.name || k.address))
      .child(card(`sub-card-${k.address}`, on, t))
      .when(!on, (el) => el.hover((s) => s.bg(dimmed(t))))
      .on_click(open)
      .child(railState(t, st, pic));
    return h_flex()
      .id(`sub-${k.address}`)
      .pl(39)
      .pr(8)
      .rounded(7)
      .h(28)
      .flex_none()
      .gap(0)
      .items_center()
      .text_size(13.5)
      .relative()
      .child(card(`sub-card-${k.address}`, on, t))
      .when(!on, (el) => el.hover((s) => s.bg(dimmed(t))))
      .on_click(open)
      .children(s.lines.map(l => div().self_start().mt(-4).w(9).h(17).mr(4).flex_none()
        .when(Boolean(l), el => el.border_l(1.5).border_color(t.input))
        .when(l === "└" || l === "├", el => el.border_b(1.5).rounded_bl(6))))
      .when(Boolean(pic), el => el.child(div().mr(8).child(pic)))
      .child(div().flex_1().truncate().text_color(on ? t.foreground : t.muted).child(k.name || k.template || k.program?.name || k.address))
      .child(this.status(t, { status: st }, compact));
  }

  // compact: a ! for blocked where a header already says "Needs you".
  status(t, a, compact = false) {
    const color = t[a.status] ?? t.dim;
    if (a.status === "working") return svg("mods/workspace-chrome/spinner.svg").size(12).mx(1).flex_none().text_color(t.working).spin(900);
    if (a.status === "blocked" && compact) return div().size(14).flex_none().rounded(4).bg(t.blocked + "26").text_size(10.5).font_bold().text_color(t.blocked).flex().items_center().justify_center().child("!");
    if (a.status === "blocked") return div().flex_none().px(6).h(18).rounded(5).bg(t.blocked + "26").text_size(10.5).font_semibold().text_color(t.blocked).flex().items_center().child("Needs you");
    // Idle: a ring; done: a dot.
    if (a.status === "idle") return div().size(7).mx(3).flex_none().rounded(4).border(1.5).border_color(t.idle ?? t.dim);
    return div().size(7).mx(3).flex_none().rounded(4).bg(a.status === "done" ? color : t.dim + "00");
  }

  render(cx) {
    const t = theme();
    if (props()?.sortMenu) return this.sortMenu(t);
    const collapsed = narrow();
    const sort = sortOf();
    let list = agents();
    this.listed = new Map(list.map((a) => [a.address, a.status]));
    const all = terminals();
    this.migratePins(all);
    const shown = focused()?.agent;
    const now = Date.now();
    this.track(list, now);
    this.hold(list);
    // A kept sub-agent (one with a pane) is in agents() too: where a tree shows
    // it, it gets no row of its own, unless it's pinned.
    // mdj: the rail nests and groups exactly as the open list does, so folding the sidebar moves no row.
    const nested = new Set(list.flatMap((a) => this.tree(all, a.address).map((s) => s.t.address)));
    list = list.filter((a) => a.pinned || !nested.has(a.address));
    const tabCounts = new Map();
    for (const a of list) tabCounts.set(a.tab, (tabCounts.get(a.tab) ?? 0) + 1);
    const byPriority = sort.id === "priority";
    const urgency = new Map(list.map((a) => [a.address, Math.max(this.rank(a), ...this.tree(all, a.address).map((s) => RANK[kidStatus(s.t, this.listed)] ?? 0))]));
    const rankOf = (a) => urgency.get(a.address);
    if (byPriority) list = [...list].sort((x, y) => rankOf(y) - rankOf(x) || this.since(y) - this.since(x) || y.seq - x.seq);
    const pinned = list.filter((a) => a.pinned);
    const rest = list.filter((a) => !a.pinned);
    list = [...pinned, ...rest];
    setAgentOrder(list.map((a) => a.address));

    const withKids = (a, i) => {
      const subs = this.tree(all, a.address);
      const r = row(a, i, subs);
      if (this.folded.has(a.address)) return [r];
      return [r, ...subs.map((s) => this.subRow(t, s, shown, byPriority, collapsed))];
    };

    // The fold chevron; folded, the count too, colored by the most urgent one.
    const fold = (a, subs) => {
      const sts = subs.map((s) => kidStatus(s.t, this.listed));
      const top = sts.reduce((m, s) => ((RANK[s] ?? 0) > (RANK[m] ?? 0) ? s : m), null);
      const open = !this.folded.has(a.address);
      return div()
        .id(`fold-${a.address}`)
        .h(18)
        .px(3)
        .gap(3)
        .flex()
        .items_center()
        .rounded(4)
        .text_size(11)
        .text_color(open ? t.dim : (t[top] ?? t.dim))
        .cursor_pointer()
        .hover((s) => s.bg((t.hover === t.canvas ? t.chrome : t.hover)).text_color(t.foreground))
        .on_click((_e, cx) => {
          cx.stop_propagation();
          open ? this.folded.add(a.address) : this.folded.delete(a.address);
          cx.notify();
        })
        .child(svg(`mods/workspace-chrome/chevron-${open ? "down" : "right"}.svg`).size(11).flex_none())
        .when(!open, (el) => el.child(String(subs.length)));
    };

    // A row reads "space \u00b7 detail": the detail is a tab someone named or the
    // agent's own title, never an automatic tab number unless two rows would
    // otherwise read the same.
    // Read the pane snapshot once: every host read copies the whole list into JS.
    const leads = leadPanes(panes());
    const tabs = new Map(spaces().flatMap(s => s.tabs).map(tab => [tab.id, tab]));
    const labels = new Map(list.map(a => {
      const tab = tabs.get(a.tab);
      const many = tabCounts.get(a.tab) > 1;
      return [a.address, tab ? title(many ? { ...tab, named: false } : tab, many ? a : leads.get(a.tab)) : (a.title || a.program?.name || "")];
    }));
    const label = (a) => labels.get(a.address);
    const detail = new Map(list.map(a => [a.address, /^\d+$/.test(label(a)) ? null : label(a)]));
    const seen = {};
    for (const a of list) { const k = `${a.space_name}\u0000${detail.get(a.address) ?? ""}`; seen[k] = (seen[k] ?? 0) + 1; }
    for (const a of list) {
      if (detail.get(a.address) == null && seen[`${a.space_name}\u0000`] > 1) detail.set(a.address, label(a));
    }

    const row = (a, i, subs = []) => {
      const pic = icon(a.program, 16, t.foreground);
      const more = detail.get(a.address);
      // An agent on another machine (`vps/t7`) says which.
      const machine = a.address.includes("/") ? a.address.split("/")[0] : null;
      if (collapsed) {
        // mdj: a rail row is a pill as wide as the window buttons above, holding one slot that is the
        // agent's state: its program's icon while idle, the spinner, a check or a ! otherwise.
        return h_flex()
          .id(`ag-${a.address}`)
          .relative()
          .w_full()
          .h(28)
          .flex_none()
          .rounded(7)
          .items_center()
          .justify_center()
          .tooltip(String(label(a) || a.program?.name || "agent"))
          .child(card(`ag-card-${a.address}`, a.focused, t))
          .when(!a.focused, (el) => el.hover((s) => s.bg(dimmed(t))))
          .on_click(() => run("pane.focus", { pane: a.pane }))
          .child(railState(t, a.status, icon(a.program, 16, t.foreground) ?? div().text_color(t.muted).child(String(i + 1))));
      }
      const when = this.since(a);
      const idle = a.status === "idle" && !a.focused;
      const isPinned = a.pinned;
      const pin = div()
        .id(`pin-${a.address}`)
        .flex_none()
        .p(2)
        .rounded(4)
        .text_color(t.dim)
        .cursor_pointer()
        .hover((s) => s.bg((t.hover === t.canvas ? t.chrome : t.hover)).text_color(t.foreground))
        .tooltip(isPinned ? "Unpin" : "Pin to the top")
        .on_click((_e, cx) => {
          cx.stop_propagation();
          run("terminal.pin", { terminal: a.address, pinned: !isPinned });
          // The row moves away from under the pointer, and no hover-out comes.
          this.hovered = null;
          cx.notify();
        })
        .child(svg(`mods/workspace-chrome/${isPinned ? "pin-off" : "pin"}.svg`).size(13));
      // Under a space header the space goes without saying; an automatic tab number says nothing.
      // Without a space header above (priority, pinned) the row names its space.
      const full = byPriority || isPinned;
      const name = full ? a.space_name || label(a) : more ?? (/^\d+$/.test(label(a)) ? a.program?.name || label(a) : label(a));
      return h_flex()
        .id(`ag-${a.address}`)
        .pl(5)
        .pr(5)
        .h(28)
        .flex_none()
        .rounded(7)
        .items_center()
        .gap(8)
        // The focused agent looks like the pane and the selected tab: the terminal's page, a soft shadow.
        .relative()
        .child(card(`ag-card-${a.address}`, a.focused, t))
        .cursor_pointer()
        .when(!a.focused, (el) => el.hover((s) => s.bg(dimmed(t))))
        .on_hover((on, cx) => {
          if (on) this.hovered = a.address;
          else if (this.hovered === a.address) this.hovered = null;
          cx.notify();
        })
        .on_click(() => run("pane.focus", { pane: a.pane }))
        .when(Boolean(pic), el => el.child(div().id(`agent-fold-${a.address}`).size(18).flex_none().flex().items_center().justify_center()
          .when(subs.length > 0, el => el.on_click((_e, cx) => {
            cx.stop_propagation();
            this.folded.has(a.address) ? this.folded.delete(a.address) : this.folded.add(a.address);
            cx.notify();
          })).child(pic)))
        .child(h_flex().flex_1().min_w(0).gap(5).items_center()
          .child(div().min_w(0).max_w(full && more ? 120 : 200).truncate().text_color(idle ? t.muted : t.foreground).child(name))
          .when(full && Boolean(more), el => el.child(div().flex_1().min_w(0).truncate().text_color(t.dim).child(`\u00b7 ${more}`))))
        .when(Boolean(machine), el => el.child(div().text_size(10).text_color(t.dim).child(machine)))
        .when(subs.length > 0, el => el.child(fold(a, subs)))
        .when(this.hovered === a.address, el => el.child(pin))
        .when(this.hovered !== a.address && Boolean(when), el => el.child(div().flex_none().text_size(11).text_color(t.dim).child(duration(now - when))))
        .child(this.status(t, a, byPriority && !isPinned));
    };

    // Groups in list order: spaces (grouped) or priority sections. Agents of a
    // space are next to each other in agents(), so neighbours make a group.
    const groups = pinned.length ? [{ id: "pinned", label: "Pinned", status: null, members: pinned }] : [];
    for (const a of rest) {
      const r = rankOf(a) || RANK.idle;
      const id = byPriority ? `sec-${r}` : `sp-${a.space}`;
      if (groups.at(-1)?.id === id) groups.at(-1).members.push(a);
      else groups.push({ id, label: byPriority ? SECTION[r] : a.space_name || "", status: byPriority ? SECTION_STATUS[r] : null, members: [a] });
    }

    // A group's header; it folds the group. Folded, it says how many and the most urgent state.
    const header = (g) => {
      const open = !this.folded.has(g.id);
      const top = g.members.reduce((m, a) => ((RANK[a.status] ?? 0) > (RANK[m] ?? 0) ? a.status : m), null);
      return h_flex()
        .id(g.id)
        .px(8)
        .pt(8)
        .h(30)
        .flex_none()
        .gap(6)
        .items_center()
        .text_size(13.5)
        .font_medium()
        .cursor_pointer()
        .hover((s) => s.text_color(t.foreground))
        .on_click((_e, cx) => {
          open ? this.folded.add(g.id) : this.folded.delete(g.id);
          cx.notify();
        })
        .child(div().truncate().text_color(t[g.status] ?? t.dim).child(g.label))
        .when(byPriority || !open, (el) => el.child(div().text_color(t.dim).child(String(g.members.length))))
        .child(div().flex_1())
        .when(!open, (el) => el
          .when(!byPriority && top && top !== "idle", (el) => el.child(this.status(t, { status: top }, true)))
          .child(svg("mods/workspace-chrome/chevron-right.svg").size(11).flex_none().text_color(t.dim)));
    };
    // On the rail a group's header is its 30px left empty.
    const rows = groups.flatMap((g) => [collapsed ? div().id(g.id).h(30).flex_none() : header(g), ...(this.folded.has(g.id) ? [] : g.members.flatMap(withKids))]);

    return splitDrag(v_flex().id("ag-root"), "agents")
      .relative()
      .overflow_hidden()
      .size_full()
      .min_h(0)
      .bg(t.canvas)
      .text_size(13.5)
      // The split from Spaces above: a rounded grip like a phone's home bar, brighter on hover,
      // sitting on the boundary the layout drags to resize the two lists.
      .child(
        h_flex()
          .id("ag-grip")
          // mdj: 8px from the 4px bar's edges to the rows either side, the gap between cards everywhere:
          // 4 here over the Spaces list's own bottom 4, and 8 under it to the first agent row.
          .h(16)
          .pt(4)
          .pb(8)
          .flex_none()
          .justify_center()
          .items_center()
          .cursor_row_resize()
          .on_hover((hovered, cx) => { this.gripHover = hovered; cx.notify(); })
          .on_mouse_down("left", (e, cx) => {
            cx.stop_propagation();
            setShared(SPLIT, { y: e.position.y, h: shared("mdj.spaces.h") ?? 200 });
          })
          .child(div().id("ag-grip-bar").h(4).rounded_full().bg(t.muted)
            // mdj: on the rail the bar stays inside the cubes' 28px, as wide as one when hovered.
            .w(collapsed ? (this.gripHover || shared(SPLIT) ? 28 : 16) : (this.gripHover || shared(SPLIT) ? 44 : 28)).opacity(this.gripHover || shared(SPLIT) ? 1 : 0)
            .transition("width", { duration: 180, easing: "ease-out" })
            .transition("opacity", { duration: 180, easing: "ease-out" })),
      )
      .when(!collapsed, (el) =>
        el.child(
          h_flex()
            .pl(12)
            .pr(4)
            .h(26)
            .flex_none()
            .items_center()
            .justify_between()
            .child(div().text_size(13.5).font_medium().text_color(t.dim).child("Agents"))
            .child(
              // mdj: the same 26px box as the Spaces + above, so the two line up with the sidebar button.
              div()
                .id("ag-sort")
                .size(26)
                .flex_none()
                .flex()
                .items_center()
                .justify_center()
                .rounded(6)
                .text_size(11)
                .text_color(t.dim)
                .hover((s) => s.bg((t.hover === t.canvas ? t.chrome : t.hover)).text_color(t.foreground))
                .on_click(() => openOverlay({ mod: "mdj-agents", kind: "popup", width: 200, height: 140, props: { sortMenu: true } }))
                .tooltip(`Sort agents: ${sort.label}`)
                .child(svg(`mods/workspace-chrome/${sort.icon}.svg`).size(14)),
            ),
        ),
      )
      // mdj: the rail keeps the header's 26px empty, so folding the sidebar leaves every row where it was.
      .when(collapsed, (el) => el.child(div().h(26).flex_none()))
      .when(list.length === 0 && !collapsed, (el) =>
        el.child(div().px(16).text_size(12).text_color(t.dim).child("No agent status yet. Agents show up here when they report their status. Older versions and agents inside tmux may not.")),
      )
      // mdj: the list is scrolled by this mod rather than by a scroll area, which tells a mod no offset, so
      // the fades are drawn from the offset the rows are drawn at and cannot drift. 4px inside the clip give
      // the focused row's shadow room to draw.
      .child(div().id("ag-list").relative().flex_1().min_h(0).overflow_hidden()
        .on_size_change((s, cx) => { if (s.height !== this.viewH) { this.viewH = s.height; cx.notify(); } })
        .on_scroll_wheel((e, cx) => { scrolled(this, e); cx.notify(); })
        .child(v_flex().id("ag-content").absolute().left(0).right(0).top(-drawnAt(this)).px(4).pb(4).gap(4)
          .on_size_change((s, cx) => { if (s.height !== this.contentH) { this.contentH = s.height; cx.notify(); } })
          .children(rows)))
      .children(fades(t, this, collapsed ? 10 : 36));
  }
}

