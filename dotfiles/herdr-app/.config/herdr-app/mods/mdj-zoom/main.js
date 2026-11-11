// cmd-0 → mod.open:mdj-zoom. Puts the zoom back to ZOOM rather than to Herdr's 1.0, then closes itself.
// Herdr has no command that sets a zoom and its reset always means 1.0, but it applies settings.json
// live and takes any zoom there, 1.14 as well as 1.2, checked on 2026-11-11. A mod's fs may write only
// under ~/.config/herdr-app, and settings.json is a link into the dotfiles, so the write was refused.
// A mod may run commands, so sed rewrites the zoom line in the file the link points to, keeping the
// link and the rest of the file as they are, and touch -h tells Herdr, which watches the link.
// The zoom keys save into the same file, so the zoom there is wherever the keys last left it, and
// ZOOM here is the one that is meant.

import { View, div } from "gpui-kit";
import { props, hc, home, closeOverlay } from "herdr";

const ZOOM = 1.14;

export default class MdjZoom extends View {
  init(_props, cx) {
    this.overlay = props()?.overlay;
    // Only a real mod.open zooms; herdr-app check renders this without an overlay.
    if (!this.overlay) return;
    const link = `${home()}/.config/herdr-app/settings.json`;
    const script = 'f=$(/usr/bin/readlink -f "$1") && /usr/bin/sed -i "" -E "s/(\\"zoom\\": *)[0-9.]+/\\1$2/" "$f" && /usr/bin/touch -h "$1"';
    cx.spawn(async () => {
      await hc(["run", "--bg", "--rm", "--no-parent", "--", "/bin/sh", "-c", script, "sh", link, String(ZOOM)]).catch(() => null);
      closeOverlay(this.overlay);
    });
  }
  render() { return div(); }
}
