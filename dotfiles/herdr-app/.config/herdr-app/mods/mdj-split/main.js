// cmd-enter → mod.open:mdj-split. Splits the focused pane along its longer side, then closes itself, so a
// wide pane splits side by side, each half then top and bottom, and so on. Herdr's pane.split takes only
// right or down, and a key reaches a mod only through mod.open, so the choice is made here.
// The pane's size comes from its terminal's cols and rows, turned into a shape by the cell's proportions.
// A Meslo cell is about 0.6em wide and 1.2em tall, scaled by the layout's cell width and line height.
// A mod pane has no terminal and splits right. cmd-d and cmd-shift-d still force a direction.

import { View, div } from "gpui-kit";
import { props, run, focused, terminals, settings, closeOverlay } from "herdr";

function direction() {
  const f = focused();
  const term = f?.terminal ? terminals().find((t) => t.address === f.terminal) : null;
  if (!term?.cols || !term?.rows) return "right";
  const s = settings();
  const w = term.cols * 0.6 * Number(s.terminal_cell_width ?? 1);
  const h = term.rows * 1.2 * Number(s.terminal_line_height ?? 1);
  return w >= h ? "right" : "down";
}

export default class MdjSplit extends View {
  init() {
    this.overlay = props()?.overlay;
    // Only a real mod.open splits; herdr-app check renders this without an overlay.
    if (!this.overlay) return;
    const dir = direction();
    closeOverlay(this.overlay);
    run("pane.split", { direction: dir });
  }
  render() { return div(); }
}
