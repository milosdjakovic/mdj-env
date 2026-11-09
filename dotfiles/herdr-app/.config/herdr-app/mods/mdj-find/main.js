// alt-z key → mod.open:mdj-find. Opens find.sh as the "fuzzy search" popup, then gets out of the way.
// The launch code is the same in mdj-git, mdj-files and mdj-find. The app refuses imports
// that resolve outside a mod's folder, and these files are links into the dotfiles, so it
// is written out in each launcher rather than shared. Change all three together.
// Opens one of the mdj-tools scripts as a titled popup over the window, the way herdr's
// plugin popups did. The script runs in its own hidden hc terminal, started in the focused
// pane's folder, and the popup closes when the script exits.


import { View, div } from "gpui-kit";
import { props, focused, panes, spaces, hc, home, openOverlay, closeOverlay } from "herdr";

const TOOLS = `${home()}/.config/herdr/tools`;
const SHIM = `${home()}/.config/herdr-app/mods/mdj-popup/herdr-shim.sh`;

async function launch(self, { script, title, width = 0.9, height = 0.9 }) {
  const f = focused();
  const space = spaces().find((s) => s.id === f?.space);
  const local = !space?.machine;
  const cwd = (local && f?.cwd) || home();
  // The terminal the popup was opened over, by hc address. A remote one can't be typed
  // into from here, so it counts as busy and find opens a new tab instead.
  const caller = local && f?.terminal ? f.terminal : "";
  const pane = panes().find((p) => p.terminal === caller);
  const free = pane?.program?.shell ? "yes" : "no";
  const notes = `${home()}/.cache/mdj-popup/${Date.now()}.notes`;

  const argv = [
    "/usr/bin/env",
    `HERDR_BIN_PATH=${SHIM}`,
    `HERDR_ACTIVE_PANE_ID=${caller}`,
    `HERDR_ACTIVE_PANE_CWD=${cwd}`,
    `MDJ_CALLER_FREE=${free}`,
    `MDJ_POPUP_NOTES=${notes}`,
    "/bin/zsh", "-lc", 'mkdir -p "${MDJ_POPUP_NOTES%/*}"; exec "$0"', `${TOOLS}/${script}`,
  ];
  const r = await hc(["run", "--bg", "--rm", "--no-parent", "--json", "--cwd", cwd, "--", ...argv]).catch(() => null);
  const address = r?.code === 0 ? JSON.parse(r.stdout).address : null;
  closeOverlay(self.overlay);
  if (!address) return;

  openOverlay({
    // mdj: Herdr's dialog frame takes no radius, so the popup draws its own. The frame is 10, the outer
    // radius every floating surface and pane card shares, padded 4, and the bar and the terminal inside
    // are 10 less 4, 6, so the curves run parallel.
    kind: "dialog", width, height, frame: "none",
    layout: { id: "mdj-popup", type: "column", padding: 4, radius: 10, background: "chrome", shadow: "lg", children: [
      { id: "mdj-popup-bar", type: "block", size: { px: 28 }, radius: 6,
        content: { mod: "mdj-popup", props: { title, terminal: address, notes } } },
      { id: "mdj-popup-term", type: "block", radius: 6, content: { terminal: address } },
    ] },
  });
}

export default class Launcher extends View {
  init(_props, cx) {
    this.overlay = props()?.overlay;
    // Only a real mod.open starts the tool; herdr-app check renders this without an overlay.
    if (!this.overlay) return;
    cx.spawn(async () => { await launch(this, { script: "find.sh", title: "fuzzy search", width: 0.8, height: 0.8 }); });
  }
  render() { return div(); }
}
