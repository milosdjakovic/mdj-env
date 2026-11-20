import { View, div, svg, image } from "gpui-kit";
import { h_flex } from "gpui-base";
import { spaces, panes, run, openOverlay, theme, window, shared, setShared, layout, settings } from "herdr";

// mdj: the selected look, the pane's own background and a soft shadow, is a layer under the row's content.
// Selecting shows it at once; a fade on switching was tried and taken out, asked for on 2026-11-09.
// A hovered row that is not selected gets the same colour at half strength and no shadow, so it never looks selected.
const card = (id, on, t, radius = 14) => div().id(id).absolute().top(0).left(0).right(0).bottom(0).rounded(radius)
  .bg(t.raised).shadow_sm().opacity(on ? 1 : 0);
const dimmed = (t) => t.raised + "80";

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// mdj: with the sidebar folded to its rail, the button that opens it, the plain sidebar outline, stands first in the tab row, in the
// cell the first tab had beside the window buttons, so it sits where the open sidebar's own button is rather
// than at the foot of the rail. It opens to the width the sidebar had, as mdj-brand's toggle does.
const railed = (sidebar) => Boolean(sidebar) && !sidebar.hidden && (sidebar.size?.px ?? Infinity) < 160;
function expandSidebar() {
  setShared("sidebar.collapsed", false);
  run("layout.resize", { id: "sidebar", px: shared("sidebar.width") ?? 276 });
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

  // mdj: closing the shown tab goes back to the tab shown before it, as a browser does, rather than to the
  // neighbour Herdr picks. Each space keeps the order its tabs were shown in. When the newest of them is gone
  // and Herdr shows another, the newest one left is selected, so opening a tab from the first of five, which
  // Herdr puts second, and closing it lands on the first again. Asked by Milos on 2026-11-15.
  followClose(space) {
    if (!space) return;
    const ids = new Set(space.tabs.map(c => c.id)), active = space.tabs.find(c => c.active)?.id;
    const shown = ((this.shownOrder ??= {})[space.id] ?? []);
    const closed = shown.length > 0 && !ids.has(shown[shown.length - 1]);
    const left = shown.filter(id => ids.has(id));
    this.shownOrder[space.id] = left;
    const back = left[left.length - 1];
    if (closed && back && back !== active) {
      this.goingBack = { id: back, until: Date.now() + 1000 };
      run("tab.select", { id: back });
      return;
    }
    // Until the selection lands, the tab Herdr picked is not one the person chose.
    if (this.goingBack) {
      if (this.goingBack.id !== active && Date.now() < this.goingBack.until) return;
      this.goingBack = null;
    }
    if (!active || back === active) return;
    this.shownOrder[space.id] = [...left.filter(id => id !== active), active].slice(-50);
  }

  // mdj: a tab's only pane shows no focus border, since there is nothing else it could be, and a split tab's
  // focused pane does, zoomed or not. Herdr's pane frame has one `focus` for every pane, so the layout holds the
  // pane block twice in the `main-stack` stack, `main` with the accent focus and `main-lone` without, and this
  // shows the one that fits. Asked by Milos on 2026-11-15.
  paneLook(space) {
    const tab = space?.tabs.find(c => c.active);
    if (!tab) return;
    const want = panes().filter(p => p.tab === tab.id).length > 1 ? "main" : "main-lone";
    const stack = find(layout(), "main-stack");
    if (!stack || stack.active === want) return;
    if (this.lookAsked?.want === want && Date.now() < this.lookAsked.until) return;
    this.lookAsked = { want, until: Date.now() + 1000 };
    run("layout.select", { stack: "main-stack", child: want });
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

  // The overlay at a tab's right end: an eased fade into the tab's own paint, then the 18px slot 5px from the edge.
  // A zoomed tab shows the zoom button's own icon in the accent in an 18px box before the slot, rather than the
  // shipped mod's " Z" after the name, and the slot stays empty until there is a status or a hover.
  // A plain tab is the canvas, a selected one the card's `background`, and a hovered one `background` at half over
  // the canvas, mixed here from the two theme colours so the fade meets the tab's colour exactly. The colour is set
  // on the rounded box itself, since a child layer is clipped square and cut the tab's right corners.
  trailing(c, t, over, status, radius) {
    const hex = (a) => Math.round(255 * a).toString(16).padStart(2, "0");
    const rgb = (h) => [1, 3, 5].map(k => parseInt(h.slice(k, k + 2), 16));
    const mix = (a, b) => "#" + rgb(a).map((v, k) => Math.round((v + rgb(b)[k]) / 2).toString(16).padStart(2, "0")).join("");
    const fill = (c.active ? t.raised : over ? mix(t.canvas, t.raised) : t.canvas).slice(0, 7);
    const n = 20;
    const slot = over
      ? div().id(`close-${c.id}`).size(18).flex_none().flex().items_center().justify_center().rounded_full().text_color(t.dim)
        .hover(s => s.bg(t.dim + "26").text_color(t.foreground))
        .on_mouse_down("left", (_e, cx) => cx.stop_propagation()).on_click((_e, cx) => { cx.stop_propagation(); run("tab.close", { id: c.id }); })
        .child(svg("mods/mdj-icons/12/x.svg").size(12))
      : div().size(18).flex_none().flex().items_center().justify_center().when(Boolean(status), el => el.child(status));
    return h_flex().absolute().top(0).bottom(0).right(0).items_stretch()
      .children(Array.from({ length: n }, (_, i) => {
        const x = (i + 0.5) / n, ease = x * x * (3 - 2 * x);
        return div().w(1).flex_none().bg(fill + hex(ease));
      }))
      .child(div().flex_none().pr(8).rounded_r(radius).bg(fill).flex().items_center()
        .when(Boolean(c.zoomed), el => el.child(div().size(18).flex_none().flex().items_center().justify_center()
          .child(svg("mods/mdj-icons/12/maximize-2.svg").size(12).text_color(t.accent))))
        .when(over || Boolean(status), el => el.child(slot)));
  }

  render() {
    const t = theme();
    const space = spaces().find(p => p.active);
    const shown = space?.tabs ?? [];
    this.followClose(space);
    this.paneLook(space);
    const stop = (_e, cx) => cx.stop_propagation();
    // mdj: every control on this bar is one size, ROW tall with RADIUS corners, like the side lists.
    const ROW = 28, RADIUS = 14, hoverBg = dimmed(t);
    const button = (id, label, action) => div().id(id).size(ROW).mt(4).flex_none().flex().items_center().justify_center().rounded(RADIUS).text_color(t.muted).hover(s => s.bg(hoverBg).text_color(t.foreground))
      .on_mouse_down("left", stop).on_click(action).child(label);
    const item = (c, i) => {
      const program = panes().find(p => p.tab === c.id && p.program?.agent)?.program ?? panes().find(p => p.tab === c.id)?.program;
      const name = /^tb\d+$/.test(c.name) ? program?.name ?? "Terminal" : c.name;
      // mdj: the tab's status, a spinner while its agent works or a dot, and the close button that takes its place
      // while the pointer is on the tab, take no width. They sit over the end of the name in an 18px slot 5px in,
      // with an eased fade on their left in whatever the tab is painted, so the name runs to the tab's edge when
      // neither shows and fades out under them when one does. Asked by Milos on 2026-11-15, to try.
      // A tab is at least four times as wide as it is tall, so a short name still makes a tab, not a chip.
      const over = this.hoverTab === c.id;
      const status = c.status === "working" ? svg("mods/workspace-chrome/spinner.svg").size(12).flex_none().text_color(t.working).spin(900)
        : c.status === "blocked" || c.status === "done" ? div().size(6).rounded(3).bg(t[c.status]) : null;
      return h_flex().id(`tab-${c.id}`).h(ROW).min_w(ROW * 4).pl(9).pr(14).gap(8).rounded(RADIUS).items_center().flex_none().text_size(13.5).relative()
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
          .when(Boolean(program?.icon), el => el.child(program.tint ? svg(program.icon).size(14) : image(program.icon).size(14))))
        .child(div().flex_1().min_w(0).max_w(170).truncate().child(name))
        .when(over || Boolean(status) || Boolean(c.zoomed), el => el.child(this.trailing(c, t, over, status, RADIUS)));
    };
    const root = layout(), sidebar = find(root, "sidebar"), w = window();
    // Old saved rails and a dragged-narrow sidebar can be smaller than the window buttons.
    const lightsPadding = w?.platform === "macos" && w.titlebar === "none" && !w.fullscreen && root?.traffic_lights
      // mdj: the buttons stand as far from the first tab as from the window's left edge, x, so they sit in
      // a cell of their own, and with the sidebar folded to its 36px rail the tabs stay put while the pane
      // moves left under the buttons. The 1.5 was measured on 2026-11-09, the strip starting 2.5px short of the
      // sum of its paddings.
      ? Math.max(10, (2 * root.traffic_lights[0] + 52) / settings().zoom - 1.5 - (sidebar?.hidden ? 0 : sidebar?.size?.px ?? 0))
      : 10;
    const panel = find(root, "panel"), body = find(root, "panel-body");
    const enabled = shared("workspace.panels") ?? ["files", "changes"];
    this.syncPanel(space, panel, body, enabled);
    const panelButton = (id, label, icon) => {
      const on = panel && !panel.hidden && body?.active === id;
      return h_flex().id(`panel-${id}`).h(ROW).mt(4).pl(9).pr(14).gap(8).flex_none().items_center().rounded(RADIUS)
        .text_size(13.5).relative().child(card(`panel-card-${id}`, on, t, RADIUS)).text_color(on ? t.foreground : t.muted)
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
      .when(railed(sidebar), el => el.child(button("sidebar-expand", svg("mods/mdj-icons/14/panel-left.svg").size(14), expandSidebar)
        .ml(lightsPadding > 10 ? 4 : 0).tooltip("Show sidebar")))
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
      .child(button("tab-new", svg("mods/mdj-icons/14/plus.svg").size(14), () => openOverlay({ mod: "new-menu", kind: "popup", width: 250, height: 512 })))
      .when(enabled.includes("files"), el => el.child(panelButton("files", "Files", "mods/mdj-icons/14/file.svg")))
      .when(enabled.includes("changes"), el => el.child(panelButton("changes", "Changes", "mods/mdj-icons/14/git-compare.svg")))
      .when(w?.buttons, el => el.child(button("minimize", w.platform === "windows" ? svg("mods/tabs/win-min.svg").size(16) : "−", () => run("window.minimize")))
        .child(button("maximize", w.platform === "windows" ? svg(`mods/tabs/${w.maximized ? "win-restore" : "win-max"}.svg`).size(16) : "□", () => run("window.maximize")))
        .child(button("close-window", w.platform === "windows" ? svg("mods/tabs/win-close.svg").size(16) : svg("mods/mdj-icons/13/x.svg").size(13), () => run("window.close"))));
  }
}
