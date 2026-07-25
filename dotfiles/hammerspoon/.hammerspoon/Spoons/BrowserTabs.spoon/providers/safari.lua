--- === BrowserTabs.providers.safari ===
---
--- The Safari backend. Safari has its own dictionary rather than the Chromium one, so it is
--- its own file, and it owns its bundle identifier the way a provider owns knowledge of its
--- own backend. Two differences from Chromium shape the code. A tab's title is `name`, not
--- `title`. And a window names its selected tab through `current tab`, an object, rather
--- than an active tab index, so the index is read back off that object.
---
--- Safari tabs carry no id at all, which is the reason tab identity across this whole spoon
--- is the bundle id plus the URL rather than a browser tab id. The consequence and its cost
--- are recorded in the spoon's CLAUDE.md.

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function loadShared(name)
  local chunk, err = loadfile(spoonPath .. "../" .. name)
  if not chunk then
    error("BrowserTabs.providers.safari: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end

local jxa = loadShared("jxa.lua")

local BUNDLE_ID = "com.apple.Safari"

-- Every tab of every window, names and URLs fetched in bulk so the cost is one Apple Event
-- per property per window. The running guard keeps a listing from ever launching Safari.
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
    try { at = win.currentTab().index(); } catch (e) {}
    try { titles = win.tabs.name(); urls = win.tabs.url(); } catch (e) { continue; }
    for (let t = 0; t < titles.length; t++) {
      out.push({ windowID: String(wid), windowIndex: w + 1, tabIndex: t + 1,
                 active: (t + 1) === at, title: titles[t], url: urls[t] });
    }
  }
  return JSON.stringify(out);
}
]==]

-- The selected tab of the frontmost window, for the recency observer. One tab, not a
-- listing, since it runs on every focus change and tab switch.
local ACTIVE = [==[
function run(argv) {
  const app = Application(argv[0]);
  if (!app.running()) return "{}";
  const wins = app.windows;
  if (wins.length === 0) return "{}";
  try {
    const t = wins[0].currentTab();
    return JSON.stringify({ title: t.name(), url: t.url() });
  } catch (e) { return "{}"; }
}
]==]

-- Select a tab and raise its window. Found by window id, since indexes shift as windows are
-- reordered and the list may be a moment old. Raising the application is the caller's job.
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
      try { win.currentTab = win.tabs[idx - 1]; } catch (e) { return JSON.stringify({ ok: false }); }
      try { win.index = 1; } catch (e) {}
      return JSON.stringify({ ok: true });
    }
  }
  return JSON.stringify({ ok: false });
}
]==]

local P = { name = "Safari", bundleID = BUNDLE_ID }

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

function P.activeTab(cb)
  jxa.run(ACTIVE, { BUNDLE_ID }, function(data, err)
    if err then cb(nil, err) return end
    if type(data) ~= "table" or not data.url then cb(nil) return end
    cb({ title = data.title, url = data.url })
  end)
end

function P.activate(tab, cb)
  jxa.run(ACTIVATE, { BUNDLE_ID, tostring(tab.windowID), tostring(tab.tabIndex) }, function(data, err)
    if err then cb(false, err) return end
    cb(type(data) == "table" and data.ok == true, nil)
  end)
end

return P
