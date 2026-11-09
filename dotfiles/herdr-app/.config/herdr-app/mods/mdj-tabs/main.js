import { View, div, svg, image } from "gpui-kit";
import { h_flex } from "gpui-base";
import { spaces, panes, run, openOverlay, theme, window, shared, layout, settings } from "herdr";

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

export default class MdjTabs extends View {
  init() {
    this.pressed = null;
    this.panels = JSON.parse(localStorage.getItem("panels") ?? "{}");
  }

  // The side panel is remembered per space: switching shows that space's choice
  // (closed if it never had one), and opening or closing it records it.
  syncPanel(space, panel, body, enabled) {
    if (!space || !panel) return;
    const now = panel.hidden ? null : body?.active ?? null;
    if (space.id !== this.space) {
      const first = this.space === undefined;
      this.space = space.id; this.pending = null;
      if (!(first && !(space.id in this.panels))) {
        const stored = this.panels[space.id] ?? null, want = enabled.includes(stored) ? stored : null;
        if (want !== now) {
          this.pending = { want, until: Date.now() + 1000 };
          if (want) { run("layout.select", { stack: "panel-body", child: want }); run("layout.show", { id: "panel" }); }
          else run("layout.hide", { id: "panel" });
          return;
        }
      }
    }
    // Until the restore lands (or something else won), the old state isn't a choice.
    if (this.pending) {
      if (this.pending.want !== now && Date.now() < this.pending.until) return;
      this.pending = null;
    }
    if (this.panels[space.id] === now) return;
    this.panels[space.id] = now;
    localStorage.setItem("panels", JSON.stringify(this.panels));
  }

  // The offset the tabs are drawn at, kept inside what the content leaves, with the active tab brought into
  // view when it changes. Each tab's width comes from its own size report, and the strip's full width is
  // their sum, since the absolutely placed row reports only the width it is shown in.
  scrolled(shown) {
    const w = (c) => this.widths?.[c.id] ?? 0;
    const z = settings().zoom ?? 1;
    this.contentW = 8 * z + shown.reduce((sum, c) => sum + w(c), 0) + 4 * z * Math.max(0, shown.length - 1);
    const max = Math.max(0, (this.contentW ?? 0) - (this.viewW ?? 0));
    const active = shown.findIndex(c => c.active);
    if (active >= 0 && shown[active].id !== this.lastActive && this.viewW) {
      this.lastActive = shown[active].id;
      const x0 = 4 * z + shown.slice(0, active).reduce((sum, c) => sum + w(c) + 4 * z, 0), x1 = x0 + w(shown[active]);
      if (x0 - 4 * z < (this.off ?? 0)) this.off = x0 - 4 * z;
      else if (x1 + 4 * z > (this.off ?? 0) + this.viewW) this.off = x1 + 4 * z - this.viewW;
    }
    this.off = Math.min(max, Math.max(0, this.off ?? 0));
    // Sizes are reported in window points and a position is set in layout px, before the zoom.
    return this.off / (settings().zoom ?? 1);
  }

  // An eased band of 1px columns at each edge with more to scroll to, the side lists' fade turned sideways.
  fades(t) {
    const max = (this.contentW ?? 0) - (this.viewW ?? 0);
    if (max <= 1) return [];
    const n = 28;
    const band = (left) => h_flex().absolute().top(0).bottom(0).w(n).when(left, el => el.left(0)).when(!left, el => el.right(-4)) // the strip clips 4px past its own box, measured, so the band reaches the cut
      .children(Array.from({ length: n }, (_, i) => {
        const x = ((left ? i : n - 1 - i) + 0.5) / n, ease = 1 - x * x * (3 - 2 * x);
        return div().w(1).h_full().flex_none().bg(t.canvas + Math.round(235 * ease).toString(16).padStart(2, "0"));
      }));
    const off = this.off ?? 0, out = [];
    if (off > 1) out.push(band(true));
    if (off < max - 1) out.push(band(false));
    return out;
  }

  render() {
    const t = theme();
    const space = spaces().find(p => p.active);
    const shown = space?.tabs ?? [];
    const stop = (_e, cx) => cx.stop_propagation();
    // mdj: every control on this bar is one size, ROW tall with RADIUS corners, like the side lists.
    const ROW = 28, RADIUS = 7, hoverBg = dimmed(t);
    const button = (id, label, action) => div().id(id).size(ROW).mt(4).flex_none().flex().items_center().justify_center().rounded(RADIUS).text_color(t.dim).hover(s => s.bg(hoverBg).text_color(t.foreground))
      .on_mouse_down("left", stop).on_click(action).child(label);
    const item = (c, i) => {
      const program = panes().find(p => p.tab === c.id && p.program?.agent)?.program ?? panes().find(p => p.tab === c.id)?.program;
      const name = /^tb\d+$/.test(c.name) ? program?.name ?? "Terminal" : c.name;
      // The right-hand slot holds the tab's status, a spinner while its agent works or a dot, and the close
      // button takes the same slot while the pointer is on the tab, so neither ever moves or resizes the tab.
      // A tab is at least four times as wide as it is tall, so a short name still makes a tab, not a chip.
      const over = this.hoverTab === c.id;
      const status = c.status === "working" ? svg("mods/workspace-chrome/spinner.svg").size(12).flex_none().text_color(t.working).spin(900)
        : c.status === "blocked" || c.status === "done" ? div().size(6).rounded(3).bg(t[c.status]) : null;
      return h_flex().id(`tab-${c.id}`).h(ROW).min_w(ROW * 4).pl(5).pr(5).gap(8).rounded(RADIUS).items_center().flex_none().text_size(13).relative()
        .child(card(`tab-card-${c.id}`, c.active, t, RADIUS)).text_color(c.active ? t.foreground : t.muted)
        .when(!c.active, el => el.hover(s => s.bg(dimmed(t))))
        .on_size_change((s, cx) => { if ((this.widths ??= {})[c.id] !== s.width) { this.widths[c.id] = s.width; cx.notify(); } })
        .on_hover((on, cx) => { if (on) this.hoverTab = c.id; else if (this.hoverTab === c.id) this.hoverTab = null; cx.notify(); })
        .on_mouse_down("left", (e, cx) => { cx.stop_propagation(); this.pressed = i; if (e.click_count === 2) run("tab.rename", { id: c.id }); })
        .on_mouse_up("left", () => {
          const from = this.pressed; this.pressed = null;
          if (from !== null && from !== i) run("tab.move", { id: shown[from].id, index: space.tabs.findIndex(x => x.id === c.id) + 1 });
          else run("tab.select", { id: c.id });
        })
        .on_mouse_down("right", (_e, cx) => { cx.stop_propagation(); openOverlay({ mod: "mdj-menu", kind: "popup", frame: "none", width: 208, props: { tab: "tab", target: { id: c.id, space: space.id } } }); })
        // The leading icon sits in an 18px box 5px in from the left, top and bottom, as on every side-list row.
        .child(div().size(18).flex_none().flex().items_center().justify_center()
          .when(Boolean(program?.icon), el => el.child(program.tint ? svg(program.icon).size(14).text_color(t.muted) : image(program.icon).size(14))))
        .child(div().flex_1().min_w(0).max_w(170).truncate().child(c.zoomed ? `${name} Z` : name))
        .child(over
          ? div().id(`close-${c.id}`).size(18).flex_none().flex().items_center().justify_center().rounded(5).text_color(t.dim)
            .hover(s => s.bg(t.canvas).text_color(t.foreground))
            .on_mouse_down("left", stop).on_click((_e, cx) => { cx.stop_propagation(); run("tab.close", { id: c.id }); })
            .child(svg("mods/pane/close.svg").size(12))
          : div().size(18).flex_none().flex().items_center().justify_center().when(Boolean(status), el => el.child(status)));
    };
    const root = layout(), sidebar = find(root, "sidebar"), w = window();
    // Old saved rails and a dragged-narrow sidebar can be smaller than the window buttons.
    const lightsPadding = w?.platform === "macos" && w.titlebar === "none" && !w.fullscreen && root?.traffic_lights
      ? Math.max(10, (root.traffic_lights[0] + 64) / settings().zoom - (sidebar?.hidden ? 0 : sidebar?.size?.px ?? 0))
      : 10;
    const panel = find(root, "panel"), body = find(root, "panel-body");
    const enabled = shared("workspace.panels") ?? ["files", "changes"];
    this.syncPanel(space, panel, body, enabled);
    const panelButton = (id, label, icon) => {
      const on = panel && !panel.hidden && body?.active === id;
      return h_flex().id(`panel-${id}`).h(ROW).mt(4).pl(5).pr(10).gap(8).flex_none().items_center().rounded(RADIUS)
        .text_size(13).relative().child(card(`panel-card-${id}`, on, t, RADIUS)).text_color(on ? t.foreground : t.muted)
        .when(!on, el => el.hover(s => s.bg(dimmed(t)))).on_mouse_down("left", stop)
        .on_click(() => {
          if (on) run("layout.hide", { id: "panel" });
          else { run("layout.select", { stack: "panel-body", child: id }); run("layout.show", { id: "panel" }); }
        }).child(div().size(18).flex_none().flex().items_center().justify_center().child(svg(icon).size(14))).child(label);
    };
    // mdj: the layout pads only 4px. The tab strip scrolls, and a scroll area clips, so its 4px of room for the
    // selected tab's shadow are inside it; the buttons on the right take theirs from the bar.
    return h_flex().size_full().min_w(0).pr(4).pl(lightsPadding > 10 ? lightsPadding - 4 : 0).gap(4).items_start().bg(t.canvas)
      .on_mouse_up("left", () => { this.pressed = null; })
      // mdj: the strip is scrolled by this mod, not by a scroll area. A scroll area tells a mod no offset, so
      // fades kept from wheel deltas drifted whenever the strip moved by itself, a fade over the first tab at
      // the start and none over a cut tab. Here the offset is the one the tabs are drawn at, so the fades are
      // always right. The wheel scrolls it and never switches tabs; a newly selected tab is scrolled into view.
      .child(div().id("tab-strip").relative().flex_1().min_w(0).h_full().overflow_hidden()
        .on_size_change((s, cx) => { if (s.width !== this.viewW) { this.viewW = s.width; cx.notify(); } })
        .on_scroll_wheel((e, cx) => {
          // A strip that scrolls only sideways takes a plain wheel's vertical delta as sideways.
          const d = Math.abs(e.delta.x) > 0 ? e.delta.x : e.delta.y;
          this.off = (this.off ?? 0) - d;
          cx.notify();
        })
        .child(h_flex().id("tab-content").absolute().top(0).left(-this.scrolled(shown)).h_full().pt(4).px(4).items_start().gap(4)
          .children(shown.map(item)))
        .children(this.fades(t)))
      .child(button("tab-new", "+", () => openOverlay({ mod: "new-menu", kind: "popup", width: 250, height: 512 })))
      .when(enabled.includes("files"), el => el.child(panelButton("files", "Files", "mods/files/file.svg")))
      .when(enabled.includes("changes"), el => el.child(panelButton("changes", "Changes", "mods/changes/changes.svg")))
      .when(w?.buttons, el => el.child(button("minimize", w.platform === "windows" ? svg("mods/tabs/win-min.svg").size(16) : "−", () => run("window.minimize")))
        .child(button("maximize", w.platform === "windows" ? svg(`mods/tabs/${w.maximized ? "win-restore" : "win-max"}.svg`).size(16) : "□", () => run("window.maximize")))
        .child(button("close-window", w.platform === "windows" ? svg("mods/tabs/win-close.svg").size(16) : svg("mods/pane/close.svg").size(13), () => run("window.close"))));
  }
}
