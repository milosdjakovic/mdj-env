import { View, div, svg } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { theme, run, props, window, shared, setShared, updates, layout, settings } from "herdr";

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

// To the rail, or back to the width it had. mdj: the rail is a column of 28px cubes in the 4px strips, 36px,
// narrower than the macOS window buttons, so the pane moves left under them and the tab bar pads itself
// clear of them and stays where it was.
const railWidth = () => 36;
function toggleSidebar() {
  const width = find(layout(), "sidebar")?.size?.px;
  if (!narrow()) setShared("sidebar.width", width);
  // Mods edited before the rail went by width still read the flag.
  setShared("sidebar.collapsed", !narrow());
  run("layout.resize", { id: "sidebar", px: narrow() ? (shared("sidebar.width") ?? 276) : railWidth() });
}

export default class MdjBrand extends View {
  button(id, label, action) {
    const t = theme();
    return div().id(id).size(26).flex_none().flex().items_center().justify_center().rounded(6).text_color(t.muted).hover(s => s.bg((t.hover === t.canvas ? t.chrome : t.hover)).text_color(t.foreground))
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation()).on_click(action).child(label);
  }
  render() {
    const t = theme();
    const collapsed = narrow();
    if (props()?.footer) {
      const row = (id, icon, label, dim, action) => h_flex().id(id).h(28).px(8).gap(9).items_center().rounded(8)
        .when(collapsed, el => el.relative().w_full().px(0).rounded(7).justify_center().tooltip(label))
        .text_color(dim ? t.dim : t.muted).hover(s => s.bg((t.hover === t.canvas ? t.chrome : t.hover)).text_color(t.foreground)).cursor_pointer()
        .on_click(action).child(svg(`mods/workspace-chrome/${icon}.svg`).size(14))
        .when(!collapsed, el => el.child(label));
      const ready = div().size(6).rounded_full().bg(t.accent);
      return v_flex().size_full().px(4).pb(4).bg(t.canvas).justify_end().text_size(13.5)
        
        .child(row("settings", "settings", "Settings", false, () => run("app.settings"))
          .when(Boolean(updates().app.ready), el => el.child(collapsed ? ready.absolute().top(5).right(6) : ready)))
        .child(row("machine", "plus", "Add machine", true, () => run("mod.open", { name: "machine-add" })));
    }
    // mdj: the layout pads 4px, the other 4px are here, so the bar lines up with the lists below, the sidebar
    // button in the same 26px box 4px from the edge as the Spaces + and the Agents sort, search beside it.
    return h_flex().size_full().bg(t.canvas).pt(4).pl(collapsed ? 10 : 18).pr(4).gap(4).items_center().text_size(13.5)
      .when(window()?.platform === "macos" && !window()?.fullscreen && !collapsed, el => el.pl(76))
      .when(!collapsed, el => el.child(div().flex_1()))
      .when(!collapsed, el => el.child(this.button("search", svg("mods/workspace-chrome/search.svg").size(15), () => run("mod.open", { name: "picker" }))))
      // mdj: open, the toggle is Herdr's sidebar outline with its left column filled, and the plain outline in the
      // tab row opens the rail. The fill is a div over the svg's column, 15/24 of its viewBox, coloured as the
      // button's text is, since Herdr ships no filled icon and draws no svg a symlink points at, so a file of
      // ours cannot be stowed.
      // mdj: on the rail the window buttons fill this row, and mdj-tabs puts the button that opens the sidebar
      // first in the tab row beside them.
      .when(!collapsed, el => el.child(this.button("sidebar-toggle", div().relative().size(15)
        .child(svg("mods/workspace-chrome/sidebar.svg").size(15))
        .child(div().absolute().left(1.9).top(2.5).w(4.1).h(10).rounded_l(1.9).bg(this.toggleOver ? t.foreground : t.muted)), toggleSidebar)
        .on_hover((on, cx) => { this.toggleOver = on; cx.notify(); })));
  }
}
