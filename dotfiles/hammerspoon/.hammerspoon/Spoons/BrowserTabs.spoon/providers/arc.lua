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
--- name rather than the active tab title, so there is no route to it. So `activeTab` answers
--- nothing and the `active` flag is false on every row. That is a real limitation of Arc's
--- dictionary rather than a gap here, and what it costs is recorded in the spoon's CLAUDE.md.

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function loadShared(name)
  local chunk, err = loadfile(spoonPath .. "../" .. name)
  if not chunk then
    error("BrowserTabs.providers.arc: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end

local jxa = loadShared("jxa.lua")

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

-- Select a tab and raise its window. The tab is told to select itself, Arc's own command,
-- and the window is found by id since indexes shift as windows are reordered. Raising the
-- application is the caller's job.
local ACTIVATE = [==[
function run(argv) {
  const app = Application(argv[0]);
  if (!app.running()) return JSON.stringify({ ok: false });
  const wid = argv[1], idx = parseInt(argv[2], 10);
  const wins = app.windows, n = wins.length;
  for (let w = 0; w < n; w++) {
    const win = wins[w];
    let id = null;
    try { id = String(win.id()); } catch (e) { continue; }
    if (id === wid) {
      try { win.tabs[idx - 1].select(); } catch (e) { return JSON.stringify({ ok: false }); }
      try { win.index = 1; } catch (e) {}
      return JSON.stringify({ ok: true });
    }
  }
  return JSON.stringify({ ok: false });
}
]==]

local P = { name = "Arc", bundleID = BUNDLE_ID }

function P.available()
  local path = hs.application.pathForBundleID(BUNDLE_ID)
  return path ~= nil and path ~= ""
end

function P.running()
  return #hs.application.applicationsForBundleID(BUNDLE_ID) > 0
end

function P.listTabs(cb)
  jxa.run(LIST, { BUNDLE_ID }, cb)
end

--- Arc reports no active tab, so this answers nothing rather than pretending. It is
--- implemented, not omitted, so the contract stays uniform and the one browser that cannot
--- answer says so in one place. The cost is that an Arc tab earns recency only when it is
--- opened through this tool, never from switching tabs inside Arc by hand.
function P.activeTab(cb)
  cb(nil)
end

function P.activate(tab, cb)
  jxa.run(ACTIVATE, { BUNDLE_ID, tostring(tab.windowID), tostring(tab.tabIndex) }, function(data, err)
    if err then cb(false, err) return end
    cb(type(data) == "table" and data.ok == true, nil)
  end)
end

return P
