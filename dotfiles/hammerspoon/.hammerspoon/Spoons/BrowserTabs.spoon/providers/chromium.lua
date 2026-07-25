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

-- Select a tab and raise its window. The window is found by id rather than by index,
-- because the indexes shift as windows are reordered and the list may be a moment old.
-- Raising the application is the caller's job, so this does not activate.
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
      try { win.activeTabIndex = idx; } catch (e) { return JSON.stringify({ ok: false }); }
      try { win.index = 1; } catch (e) {}
      return JSON.stringify({ ok: true });
    }
  }
  return JSON.stringify({ ok: false });
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
    return #hs.application.applicationsForBundleID(bundleID) > 0
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
    jxa.run(ACTIVATE, { bundleID, tostring(tab.windowID), tostring(tab.tabIndex) }, function(data, err)
      if err then cb(false, err) return end
      cb(type(data) == "table" and data.ok == true, nil)
    end)
  end

  return P
end
