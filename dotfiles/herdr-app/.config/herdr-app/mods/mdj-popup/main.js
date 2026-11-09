// The title bar of an mdj tool popup, and the code that opens one (launch.js).
// It names the popup, closes it with ×, and when the popup goes it ends the tool's
// terminal and posts whatever the tool asked herdr to notify as app toasts.

import { View, div } from "gpui-kit";
import { h_flex } from "gpui-base";
import { props, theme, closeOverlay, notify, readTextFile, exec, hc } from "herdr";

export default class PopupBar extends View {
  init() {
    this.p = props() ?? {};
  }

  async close() {
    const { terminal, notes } = this.p;
    if (terminal) await hc(["kill", terminal]).catch(() => null);
    if (!notes) return;
    const text = await readTextFile(notes).catch(() => null);
    for (const line of (text ?? "").split("\n").filter(Boolean)) {
      const [title, body] = line.split("\t");
      notify({ title, body, level: "info" });
    }
    await exec("rm", ["-f", notes]).catch(() => null);
  }

  render() {
    const t = theme();
    return h_flex().id("root").size_full().px(12).justify_between().items_center()
      .bg(t.chrome).border_b(1).border_color(t.border).text_size(12)
      .child(div().text_color(t.muted).child(this.p.title ?? "popup"))
      .child(div().id("close").px(6).rounded(4).text_color(t.dim)
        .hover((s) => s.bg(t.hover).text_color(t.foreground))
        .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
        .on_click(() => closeOverlay(this.p.overlay))
        .child("×"));
  }
}
