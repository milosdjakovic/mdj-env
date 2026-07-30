--- === BrowserTabs.providers.chromium ===
---
--- The Chromium family backend. Chrome, Brave, Edge, Vivaldi and Opera all ship the same
--- AppleScript dictionary, tabs carrying title and URL and a window carrying an active tab
--- index, so one implementation drives every one of them and five near identical files
--- would be copy paste rather than design.
---
--- That is why this file alone is a factory while the other providers are plain modules. A
--- provider owns knowledge of its own backend, and this backend is a dictionary shared by
--- many applications, so which application is genuinely a parameter. The composition root
--- names the concrete browsers by calling this once each. Nothing in here learns which
--- Chromium it is driving.

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function loadShared(name)
  local chunk, err = loadfile(spoonPath .. "../" .. name)
  if not chunk then
    error("BrowserTabs.providers.chromium: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end

local jxa = loadShared("jxa.lua")
local apps = loadShared("apps.lua")

-- Every tab of every window, titles and URLs fetched in bulk so the cost is one Apple
-- Event per property per window rather than per tab. The running guard is belt and braces
-- over the engine's own check, because addressing a specifier on a quit app would launch
-- it, and being asked for its tabs must never start a browser. A window that throws is
-- skipped rather than failing the whole listing, so one bad window cannot hide the rest.
local LIST = [==[
function run(argv) {
  const app = Application(argv[0]);
  if (!app.running()) return "[]";
  const out = [];
  const wins = app.windows, n = wins.length;
  for (let w = 0; w < n; w++) {
    const win = wins[w];
    let wid = null, at = -1, titles = [], urls = [];
    try { wid = win.id(); } catch (e) {}
    try { at = win.activeTabIndex(); } catch (e) {}
    try { titles = win.tabs.title(); urls = win.tabs.url(); } catch (e) { continue; }
    for (let t = 0; t < titles.length; t++) {
      out.push({ windowID: String(wid), windowIndex: w + 1, tabIndex: t + 1,
                 active: (t + 1) === at, title: titles[t], url: urls[t] });
    }
  }
  return JSON.stringify(out);
}
]==]

-- The selected tab of the frontmost window, for the recency observer. Deliberately reads
-- one tab rather than listing, since it runs on every focus change and tab switch.
local ACTIVE = [==[
function run(argv) {
  const app = Application(argv[0]);
  if (!app.running()) return "{}";
  const wins = app.windows;
  if (wins.length === 0) return "{}";
  try {
    const win = wins[0];
    const t = win.tabs[win.activeTabIndex() - 1];
    return JSON.stringify({ title: t.title(), url: t.url() });
  } catch (e) { return "{}"; }
}
]==]

-- Select a tab and bring its window forward. The window is addressed by id through the shared
-- `windowById`, never by its position, for the reason recorded in jxa.lua, that both of the
-- writes below reorder the window list and a positional specifier would then be pointing at
-- another window. Raising the application is the caller's job, so this does not activate.
--
-- A minimized window is restored, since raising the application leaves it in the Dock and the
-- whole thing then looks like it did nothing at all. The Chromium dictionary calls that state
-- `minimized`, which is why restoring it belongs in each provider rather than in the engine,
-- Safari naming the same state something else. Ordering between the restore and the reorder was
-- measured both ways and neither is better once the window is addressed by id, so the reorder
-- goes last simply because the window order is the thing the raise then honours.
--
-- The window's own name is read back afterwards and returned, since the caller has to find this
-- same window at the accessibility layer and a Chromium window id means nothing there. It is read
-- after the tab switch so it names the tab that was asked for. Chrome elides a long one in the
-- middle with an ellipsis, which no accessibility title ever carries, so the caller cannot rely on
-- this alone and does not. That is measured, not assumed.
local ACTIVATE = [==[
function run(argv) {
  const app = Application(argv[0]);
  if (!app.running()) return JSON.stringify({ ok: false });
  const win = windowById(app, argv[1]);
  if (!win) return JSON.stringify({ ok: false });

  // The tab was numbered when the list was built and the numbers move whenever a tab is opened or
  // closed in the meantime, so the position is checked against the URL that came with it and only
  // trusted when the two still agree. The position is preferred rather than the URL because a
  // window very often holds the same address more than once, and when nothing has drifted the
  // position is the one that says which of them was meant.
  let idx = parseInt(argv[2], 10);
  try {
    const urls = win.tabs.url();
    const want = argv[3] || "";
    if (want && urls[idx - 1] !== want) {
      const found = urls.indexOf(want);
      if (found >= 0) idx = found + 1;
    }
  } catch (e) {}

  try { win.activeTabIndex = idx; } catch (e) { return JSON.stringify({ ok: false }); }
  try { if (win.minimized()) win.minimized = false; } catch (e) {}
  try { win.index = 1; } catch (e) {}
  const r = { ok: true };
  try { r.name = win.name(); } catch (e) {}
  return JSON.stringify(r);
}
]==]

--- The factory. opts.name is the human browser name and opts.bundleID its bundle
--- identifier, both required, since without them this file cannot know which Chromium the
--- root meant.
return function(opts)
  opts = opts or {}
  local name, bundleID = opts.name, opts.bundleID
  if type(name) ~= "string" or name == "" then
    error("BrowserTabs.providers.chromium: a name is required")
  end
  if type(bundleID) ~= "string" or bundleID == "" then
    error("BrowserTabs.providers.chromium: a bundleID is required")
  end

  local P = { name = name, bundleID = bundleID }

  function P.available()
    local path = hs.application.pathForBundleID(bundleID)
    return path ~= nil and path ~= ""
  end

  function P.running()
    return apps.isRunning(bundleID)
  end

  function P.listTabs(cb)
    jxa.run(LIST, { bundleID }, cb)
  end

  function P.activeTab(cb)
    jxa.run(ACTIVE, { bundleID }, function(data, err)
      if err then cb(nil, err) return end
      if type(data) ~= "table" or not data.url then cb(nil) return end
      cb({ title = data.title, url = data.url })
    end)
  end

  function P.activate(tab, cb)
    local argv = { bundleID, tostring(tab.windowID), tostring(tab.tabIndex), tostring(tab.url or "") }
    jxa.run(ACTIVATE, argv, function(data, err)
      if err then cb(false, err) return end
      cb(type(data) == "table" and data.ok == true, nil, type(data) == "table" and data or nil)
    end)
  end

  return P
end
