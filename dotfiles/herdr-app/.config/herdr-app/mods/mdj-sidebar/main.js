// alt-z b → mod.open:mdj-sidebar. Folds the sidebar to its rail or opens it to the width it had, as
// mdj-brand's toggle does, then closes itself. A key can reach a mod only through mod.open, and
// layout.toggle hides the sidebar outright, so the key needs this. The toggle is the same as
// mdj-brand's toggleSidebar, written out here because a mod cannot import from another. Change both together.

import { View, div } from "gpui-kit";
import { props, run, shared, setShared, layout, closeOverlay } from "herdr";

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

const narrow = () => (find(layout(), "sidebar")?.size?.px ?? Infinity) < 160;
const railWidth = () => 36;
function toggleSidebar() {
  const sidebar = find(layout(), "sidebar");
  // A sidebar hidden some other way comes back open rather than staying hidden.
  if (sidebar?.hidden) { run("layout.show", { id: "sidebar" }); return; }
  if (!narrow()) setShared("sidebar.width", sidebar?.size?.px);
  setShared("sidebar.collapsed", !narrow());
  run("layout.resize", { id: "sidebar", px: narrow() ? (shared("sidebar.width") ?? 276) : railWidth() });
}

export default class MdjSidebar extends View {
  init() {
    this.overlay = props()?.overlay;
    // Only a real mod.open toggles; herdr-app check renders this without an overlay.
    if (!this.overlay) return;
    toggleSidebar();
    closeOverlay(this.overlay);
  }
  render() { return div(); }
}
