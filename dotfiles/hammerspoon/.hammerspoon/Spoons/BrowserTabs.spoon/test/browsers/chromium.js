// The Chromium family adapter for the harness. It arranges the browser into the state a case
// needs and reads back what the browser itself believes, which is one of the two witnesses every
// round is judged on. The other witness is the accessibility layer, read by ax.js from outside.
//
// This mirrors the split the spoon already has. One adapter per dictionary rather than per
// application, so Chrome, Brave, Edge, Vivaldi and Opera all come through here and the bundle id
// is a parameter. Nothing in this file learns which Chromium it is driving.
//
// It deliberately does not filter anything out of a listing. The spoon filters, and a harness
// that applied the same filter could never catch the spoon failing to.
//
// Called as osascript -l JavaScript chromium.js <bundleID> <op> <args...> and it answers with one
// JSON object on stdout, always carrying ok, so the runner never has to tell an empty answer from
// a failed one.

function run(argv) {
  const bundleID = argv[0];
  const op = argv[1];
  const args = argv.slice(2);

  const app = Application(bundleID);
  if (!app.running()) return JSON.stringify({ ok: false, err: "not running" });

  function windowById(id) {
    const want = String(id);
    const wins = app.windows;
    for (let i = 0; i < wins.length; i++) {
      try { if (String(wins[i].id()) === want) return wins[i]; } catch (e) {}
    }
    return null;
  }

  function boundsOf(win) {
    try {
      const b = win.bounds();
      return { x: b.x, y: b.y, w: b.width, h: b.height };
    } catch (e) { return null; }
  }

  function describe(win, index) {
    const out = { index: index, id: null, bounds: null, minimized: null, activeTabIndex: -1, tabs: [] };
    try { out.id = String(win.id()); } catch (e) {}
    try { out.minimized = win.minimized(); } catch (e) {}
    try { out.activeTabIndex = win.activeTabIndex(); } catch (e) {}
    out.bounds = boundsOf(win);
    let titles = [], urls = [];
    try { titles = win.tabs.title(); urls = win.tabs.url(); } catch (e) { return out; }
    for (let t = 0; t < titles.length; t++) {
      out.tabs.push({ index: t + 1, title: titles[t], url: urls[t] });
    }
    return out;
  }

  const ops = {};

  // Every window and every tab, unfiltered.
  ops.list = function () {
    const out = [];
    const wins = app.windows;
    for (let i = 0; i < wins.length; i++) out.push(describe(wins[i], i + 1));
    return { ok: true, windows: out };
  };

  // What the browser believes is in front and which tab that window is showing. This is the
  // witness that says the right tab was selected in the right window.
  ops.front = function () {
    const wins = app.windows;
    if (wins.length === 0) return { ok: true, window: null };
    return { ok: true, window: describe(wins[0], 1) };
  };

  ops.select = function () {
    const win = windowById(args[0]);
    if (!win) return { ok: false, err: "no such window" };
    win.activeTabIndex = parseInt(args[1], 10);
    return { ok: true };
  };

  ops.raise = function () {
    const win = windowById(args[0]);
    if (!win) return { ok: false, err: "no such window" };
    win.index = 1;
    return { ok: true };
  };

  // Push a window behind every other window of the same browser, which is how a target is put
  // into the background without involving another application.
  ops.back = function () {
    const win = windowById(args[0]);
    if (!win) return { ok: false, err: "no such window" };
    win.index = app.windows.length;
    return { ok: true };
  };

  ops.minimize = function () {
    const win = windowById(args[0]);
    if (!win) return { ok: false, err: "no such window" };
    win.minimized = args[1] === "1";
    return { ok: true };
  };

  // A new tab at the end of a window, answering with where it landed so a case can target it.
  ops.open = function () {
    const win = windowById(args[0]);
    if (!win) return { ok: false, err: "no such window" };
    const tab = app.Tab({ url: args[1] });
    win.tabs.push(tab);
    return { ok: true, index: win.tabs.length };
  };

  // A new tab inserted before a given position, which is what makes the tab numbers move under a
  // listing that has already been taken.
  ops.insert = function () {
    const win = windowById(args[0]);
    if (!win) return { ok: false, err: "no such window" };
    const at = parseInt(args[1], 10);
    const tab = app.Tab({ url: args[2] });
    win.tabs.insert(tab, { at: win.tabs[at - 1] });
    return { ok: true, index: at };
  };

  // A new window, found afterwards by which id is new rather than by what make returned.
  //
  // What make returns is a positional specifier, window 1, and the browser needs a moment to put
  // the new window there. Writing a URL through that specifier too early therefore navigates
  // whichever window was in front, and this harness did exactly that once, sending a real window
  // of the person's to a fixture page and then closing it as though it were one of its own. The
  // ids are the only thing that cannot be aimed at the wrong window, which is the same lesson the
  // spoon under test learned about activating a tab.
  ops.openwin = function () {
    const before = {};
    const wins = app.windows;
    for (let i = 0; i < wins.length; i++) {
      try { before[String(wins[i].id())] = true; } catch (e) {}
    }

    app.Window().make();

    // Polled rather than waited on a fixed delay, since every read here is an Apple Event round
    // trip and that is the wait. A fixed delay would be either a guess that is too short or time
    // spent doing nothing.
    let id = null;
    for (let attempt = 0; attempt < 30 && !id; attempt++) {
      const now = app.windows;
      for (let i = 0; i < now.length; i++) {
        let wid = null;
        try { wid = String(now[i].id()); } catch (e) { continue; }
        if (!before[wid]) { id = wid; break; }
      }
    }
    if (!id) return { ok: false, err: "no new window appeared" };

    if (args[0]) {
      const win = windowById(id);
      if (!win) return { ok: false, err: "the new window vanished" };
      // The tab is addressed by position within this window rather than through the window's
      // active tab property, because writing through that property on a window reached by id
      // silently does nothing, which left the new window sitting on its blank page.
      win.tabs[0].url = args[0];
    }
    return { ok: true, id: id };
  };

  // Closing a tab requires proof that it is one of ours. The caller passes a fragment that must
  // appear in the tab's address, and a tab that does not carry it is left alone.
  //
  // This is here rather than in the caller because a caller got it wrong and it cost somebody a
  // window. A disturbance closed a tab by position, on the assumption that the position still held
  // what it had put there, and when the insert before it had quietly failed the position held a
  // real page instead. Closing it emptied the window and the browser closed the window with it, so
  // a guard that only refused to close windows was never going to be enough.
  ops.close = function () {
    const win = windowById(args[0]);
    if (!win) return { ok: false, err: "no such window" };
    const tab = win.tabs[parseInt(args[1], 10) - 1];
    if (!tab) return { ok: false, err: "no such tab" };
    const must = args[2] || "";
    let url = "";
    try { url = String(tab.url() || ""); } catch (e) {}
    if (!must || url.indexOf(must) < 0) {
      return { ok: false, err: "refusing to close a tab this suite did not open, " + url };
    }
    tab.close();
    return { ok: true };
  };

  ops.closewin = function () {
    const win = windowById(args[0]);
    if (!win) return { ok: false, err: "no such window" };
    win.close();
    return { ok: true };
  };

  // Move a tab into another window. Used by the case where the chosen tab is no longer in the
  // window the listing recorded it in, which no amount of index checking inside that window can
  // recover from and which must therefore fail visibly rather than land somewhere else.
  ops.move = function () {
    const from = windowById(args[0]);
    const to = windowById(args[2]);
    if (!from || !to) return { ok: false, err: "no such window" };
    const tab = from.tabs[parseInt(args[1], 10) - 1];
    app.move(tab, { to: to.tabs });
    return { ok: true };
  };

  ops.activate = function () {
    app.activate();
    return { ok: true };
  };

  const fn = ops[op];
  if (!fn) return JSON.stringify({ ok: false, err: "unknown op " + op });
  try {
    return JSON.stringify(fn());
  } catch (e) {
    return JSON.stringify({ ok: false, err: String(e) });
  }
}
