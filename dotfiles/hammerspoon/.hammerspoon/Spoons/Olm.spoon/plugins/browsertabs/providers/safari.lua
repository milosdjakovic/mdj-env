--- === BrowserTabs.providers.safari ===
---
--- The Safari backend. Safari has its own dictionary rather than the Chromium one, so it is
--- its own file, and it owns its bundle identifier the way a provider owns knowledge of its
--- own backend. Three differences from Chromium shape the code. A tab's title is `name`, not
--- `title`. A window names its selected tab through `current tab`, an object, rather than an
--- active tab index, so the index is read back off that object. And a minimized window is
--- `miniaturized` here and `minimized` there.
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
local apps = loadShared("apps.lua")

local BUNDLE_ID = "com.apple.Safari"

-- Every tab of every window, names and URLs fetched in bulk so the cost is one Apple Event
-- per property per window. The running guard keeps a listing from ever launching Safari.
--
-- A window with no document is skipped. Safari keeps at least one window in its dictionary that
-- is not on screen at all, a leftover carrying a single Start Page tab, and it is invisible to
-- the accessibility layer, so a row offered for it can be chosen and then nothing happens, which
-- is one of the ways this tool looked like it was failing. The test is the document rather than
-- the `visible` flag, because a minimized window is not visible either, and neither is any window
-- of an application hidden with Command H, so filtering on that would throw away real tabs. A
-- window genuinely showing the Start Page still has a document, so this only ever drops the
-- phantom, all three cases measured rather than assumed.
local LIST = [==[
function run(argv) {
  const app = Application(argv[0]);
  if (!app.running()) return "[]";
  const out = [];
  const wins = app.windows, n = wins.length;
  for (let w = 0; w < n; w++) {
    const win = wins[w];
    let wid = null, at = -1, titles = [], urls = [];
    try { if (!win.document()) continue; } catch (e) { continue; }
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

-- Select a tab and bring its window forward. The window is addressed by id through the shared
-- `windowById`, never by its position, for the reason recorded in jxa.lua, that both of the
-- writes below reorder the window list and a positional specifier would then be pointing at
-- another window. Raising the application is the caller's job.
--
-- A minimized window is restored, since raising the application leaves it in the Dock and the
-- whole thing then looks like it did nothing at all. Safari calls that state `miniaturized`, the
-- Standard Suite spelling, where the Chromium dictionary says `minimized`, which is the third
-- difference that earns this file its own copy of the activation. Ordering between the restore
-- and the reorder was measured both ways on this browser too, and neither is better once the
-- window is addressed by id.
--
-- The window's own name is read back afterwards and returned, since the caller has to find this
-- same window at the accessibility layer. Safari's window ids happen to be the window server's own
-- so the caller usually matches on those, but the name is what covers a window it cannot. Safari
-- names a window after its tab group as well as the selected tab, which is exactly why the tab's
-- title cannot stand in for this.
local ACTIVATE = [==[
function run(argv) {
  const app = Application(argv[0]);
  if (!app.running()) return JSON.stringify({ ok: false });
  const win = windowById(app, argv[1]);
  if (!win) return JSON.stringify({ ok: false });

  // The tab numbers move whenever a tab is opened or closed after the list was built, so the
  // position is checked against the URL and only trusted when the two still agree. The position
  // wins when they do, since a window often holds the same address more than once.
  let idx = parseInt(argv[2], 10);
  try {
    const urls = win.tabs.url();
    const want = argv[3] || "";
    if (want && urls[idx - 1] !== want) {
      const found = urls.indexOf(want);
      if (found >= 0) idx = found + 1;
    }
  } catch (e) {}

  try { win.currentTab = win.tabs[idx - 1]; } catch (e) { return JSON.stringify({ ok: false }); }
  try { if (win.miniaturized()) win.miniaturized = false; } catch (e) {}
  try { win.index = 1; } catch (e) {}
  const r = { ok: true };
  try { r.name = win.name(); } catch (e) {}
  return JSON.stringify(r);
}
]==]

local P = { name = "Safari", bundleID = BUNDLE_ID }

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
