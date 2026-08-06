// The Safari adapter for the harness, the same shape as the Chromium one and separate for the
// same reason the providers are separate. Safari has its own dictionary. A tab's title is name, a
// window names its selected tab through an object rather than an index, and a minimized window is
// miniaturized here.
//
// This one carries an extra field the Chromium adapter has no use for. Every window reports
// whether it has a document, because Safari keeps at least one window that has none, is not on
// screen, and is invisible to the accessibility layer. The spoon must drop that window from its
// listing and this adapter must not, since a harness that hid the phantom could never prove the
// spoon hides it.
//
// Called as osascript -l JavaScript safari.js <bundleID> <op> <args...> answering one JSON object.

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

  function hasDocument(win) {
    try { return !!win.document(); } catch (e) { return false; }
  }

  function describe(win, index) {
    const out = { index: index, id: null, bounds: null, minimized: null, activeTabIndex: -1,
                  document: hasDocument(win), tabs: [] };
    try { out.id = String(win.id()); } catch (e) {}
    try { out.minimized = win.miniaturized(); } catch (e) {}
    try { out.activeTabIndex = win.currentTab().index(); } catch (e) {}
    try {
      const b = win.bounds();
      out.bounds = { x: b.x, y: b.y, w: b.width, h: b.height };
    } catch (e) {}
    let titles = [], urls = [];
    try { titles = win.tabs.name(); urls = win.tabs.url(); } catch (e) { return out; }
    for (let t = 0; t < titles.length; t++) {
      out.tabs.push({ index: t + 1, title: titles[t], url: urls[t] });
    }
    return out;
  }

  const ops = {};

  // Every window, phantom included, since proving the phantom is filtered means seeing it here.
  ops.list = function () {
    const out = [];
    const wins = app.windows;
    for (let i = 0; i < wins.length; i++) out.push(describe(wins[i], i + 1));
    return { ok: true, windows: out };
  };

  // The front window as Safari itself orders them. The phantom has never been observed in front,
  // but it is reported rather than skipped so a round can say so if it ever is.
  ops.front = function () {
    const wins = app.windows;
    if (wins.length === 0) return { ok: true, window: null };
    return { ok: true, window: describe(wins[0], 1) };
  };

  ops.select = function () {
    const win = windowById(args[0]);
    if (!win) return { ok: false, err: "no such window" };
    win.currentTab = win.tabs[parseInt(args[1], 10) - 1];
    return { ok: true };
  };

  ops.raise = function () {
    const win = windowById(args[0]);
    if (!win) return { ok: false, err: "no such window" };
    win.index = 1;
    return { ok: true };
  };

  ops.back = function () {
    const win = windowById(args[0]);
    if (!win) return { ok: false, err: "no such window" };
    win.index = app.windows.length;
    return { ok: true };
  };

  ops.minimize = function () {
    const win = windowById(args[0]);
    if (!win) return { ok: false, err: "no such window" };
    win.miniaturized = args[1] === "1";
    return { ok: true };
  };

  ops.open = function () {
    const win = windowById(args[0]);
    if (!win) return { ok: false, err: "no such window" };
    win.tabs.push(app.Tab({ url: args[1] }));
    return { ok: true, index: win.tabs.length };
  };

  ops.insert = function () {
    const win = windowById(args[0]);
    if (!win) return { ok: false, err: "no such window" };
    const at = parseInt(args[1], 10);
    win.tabs.insert(app.Tab({ url: args[2] }), { at: win.tabs[at - 1] });
    return { ok: true, index: at };
  };

  // A new window, identified by which id is new rather than by taking whatever is in front. Writing
  // to the front window right after asking for a new one navigates whichever window the browser
  // still had there, and this harness once did that to a real window of the person's and then
  // closed it as one of its own.
  ops.openwin = function () {
    const before = {};
    const wins = app.windows;
    for (let i = 0; i < wins.length; i++) {
      try { before[String(wins[i].id())] = true; } catch (e) {}
    }

    // The address is given to the document as it is made. Setting it afterwards through the new
    // window silently does nothing here, which left the window sitting on whatever page Safari
    // opens a new window with.
    if (args[0]) { app.Document({ url: args[0] }).make(); } else { app.Document().make(); }

    // Polled rather than waited on a fixed delay, since every read here is an Apple Event round
    // trip and that is the wait.
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

  // Safari has no scriptable way to move a tab between windows, so this says so rather than
  // pretending. The runner reports the case as not covered instead of quietly passing it.
  ops.move = function () {
    return { ok: false, err: "safari cannot move a tab between windows by script" };
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
