--- === BrowserTabs.providers.arc ===
---
--- The Arc backend. Arc's dictionary is close to the Chromium one for reading, tabs carrying
--- a title and a URL, but it differs in three ways that earn it its own file.
---
--- A tab carries a `location`, either topApp, pinned or unpinned, which is Arc's own notion
--- of where the tab sits in the sidebar. It is passed through as the tab's group, the only
--- provider that fills that field in, so the rows can say which part of Arc a tab came from.
---
--- Selecting a tab is a command on the tab, `select`, rather than an index set on the window.
---
--- And Arc reports no active tab. A window's `active tab` returns null, verified both while
--- Arc was in the background and while it was frontmost, and a window's `name` is the space
--- name rather than the active tab title, so there is no route to it. So the `active` flag is
--- false on every row. That is a real limitation of Arc's dictionary rather than a gap here,
--- and what it costs is recorded in the spoon's CLAUDE.md.

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function loadShared(name)
  local chunk, err = loadfile(spoonPath .. "../" .. name)
  if not chunk then
    error("BrowserTabs.providers.arc: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end

local jxa = loadShared("jxa.lua")
local apps = loadShared("apps.lua")

local BUNDLE_ID = "company.thebrowser.Browser"

-- Every tab of every window, titles, URLs and locations fetched in bulk so the cost is one
-- Apple Event per property per window rather than per tab, which on an Arc holding a hundred
-- tabs is the difference between a tenth of a second and three seconds. The locations are
-- best effort, a failure there leaves the groups empty rather than losing the listing.
local LIST = [==[
function run(argv) {
  const app = Application(argv[0]);
  if (!app.running()) return "[]";
  const out = [];
  const wins = app.windows, n = wins.length;
  for (let w = 0; w < n; w++) {
    const win = wins[w];
    let wid = null, titles = [], urls = [], locs = [];
    try { wid = win.id(); } catch (e) {}
    try { titles = win.tabs.title(); urls = win.tabs.url(); } catch (e) { continue; }
    try { locs = win.tabs.location(); } catch (e) {}
    for (let t = 0; t < titles.length; t++) {
      out.push({ windowID: String(wid), windowIndex: w + 1, tabIndex: t + 1,
                 active: false, title: titles[t], url: urls[t],
                 group: locs[t] || null });
    }
  }
  return JSON.stringify(out);
}
]==]

-- Select a tab and bring its window forward. The tab is told to select itself, Arc's own command.
-- The window is addressed by id through the shared `windowById`, never by its position, for the
-- reason recorded in jxa.lua. Raising the application is the caller's job.
--
-- A minimized window is restored, since raising the application leaves it in the Dock and the
-- whole thing then looks like it did nothing at all. Arc keeps the Chromium spelling, `minimized`,
-- and declares its window id under the same code the other two do, both read from its own sdef
-- rather than guessed at, which is as far as this can be taken without Arc running.
local ACTIVATE = [==[
function run(argv) {
  const app = Application(argv[0]);
  if (!app.running()) return JSON.stringify({ ok: false });
  let idx = parseInt(argv[2], 10);
  const win = windowById(app, argv[1]);
  if (!win) return JSON.stringify({ ok: false });
  // The tab numbers move whenever a tab is opened or closed after the list was built, so the
  // position is checked against the URL and only trusted when the two still agree. The position
  // wins when they do, since a window often holds the same address more than once.
  try {
    const urls = win.tabs.url();
    const want = argv[3] || "";
    if (want && urls[idx - 1] !== want) {
      const found = urls.indexOf(want);
      if (found >= 0) idx = found + 1;
    }
  } catch (e) {}
  try { win.tabs[idx - 1].select(); } catch (e) { return JSON.stringify({ ok: false }); }
  try { if (win.minimized()) win.minimized = false; } catch (e) {}
  try { win.index = 1; } catch (e) {}
  const r = { ok: true };
  // The window's own name, which the caller needs to find this window at the accessibility layer.
  // Arc names a window after its space rather than after the selected tab, so this one is expected
  // to be the weakest of the three, and it is still better than the tab title, which for Arc names
  // nothing the window ever shows.
  try { r.name = win.name(); } catch (e) {}
  return JSON.stringify(r);
}
]==]

local P = { name = "Arc", bundleID = BUNDLE_ID }

function P.available()
  local path = hs.application.pathForBundleID(BUNDLE_ID)
  return path ~= nil and path ~= ""
end

function P.running()
  return apps.isRunning(BUNDLE_ID)
end

function P.listTabs(cb)
  jxa.run(LIST, { BUNDLE_ID }, cb)
end

function P.activate(tab, cb)
  local argv = { BUNDLE_ID, tostring(tab.windowID), tostring(tab.tabIndex), tostring(tab.url or "") }
  jxa.run(ACTIVATE, argv, function(data, err)
    if err then cb(false, err) return end
    cb(type(data) == "table" and data.ok == true, nil, type(data) == "table" and data or nil)
  end)
end

return P
