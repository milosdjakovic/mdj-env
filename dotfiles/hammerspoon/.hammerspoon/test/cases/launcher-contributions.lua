-- Unit case for the rows other plugins contribute to the launcher's own catalog, phase three of
-- the core split. Capture, the window manager and System Settings each answer their own rows
-- through provides.launcherRows and run a chosen one through provides.launcherRun, and the
-- launcher routes a chosen row by the owner the composition root stamps on its item. Before
-- that the launcher held seven siblings on four plugins and built these rows itself.
--
-- What is asserted is what a person sees and what the launcher remembers. The titles, the
-- subtitles, the icon keys, the order of an untouched list, and the kind and identifying field
-- every item carries, since the recency memory persisted in hs.settings is keyed by those and a
-- change would make the launcher forget every pick made before it. The expected words were
-- read off the launcher as it built these rows before the change, by a one off comparison run
-- against the previous commit, which found every field equal except the owner an icon key is
-- read against. The window rows and the settings search row read theirs against the plugin
-- that built them now, which declares the same emoji and the same SF Symbol the launcher did,
-- so the picture is unchanged.
--
-- Then one row per kind is run through the launcher's own dispatcher and must reach the right
-- runner with the right argument. Every plugin method that would act on the world, take a
-- screenshot, move a window, open a pane, is replaced by a recorder on a fresh copy of the
-- module, so nothing here touches the running config. The deferred run is fired by hand
-- rather than waited for, and stopped, so the case stays synchronous.
--
-- Fresh copies throughout, each module loaded with loadfile straight out of this checkout, so
-- the instance the live config holds is never reached. Under a plain lua interpreter with no
-- Hammerspoon at all, a small stub stands in, which is how the comparison above was run.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local spoon = caseDir .. "/../../Spoons/Olm.spoon/"

if hs == nil then
  hs = {
    settings = { get = function() return nil end, set = function() end },
    processInfo = { bundleID = "org.hammerspoon.Hammerspoon" },
    logger = { new = function()
      return setmetatable({}, { __index = function() return function() end end })
    end },
    timer = { doAfter = function(_, fn) return { fire = function() fn() end, stop = function() end } end },
    image = { imageFromAppBundle = function() return nil end },
  }
end

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  elseif detail then
    print("FAIL " .. description .. ", " .. detail)
  else
    print("FAIL " .. description)
  end
end

local function eq(description, got, want)
  check(description, got == want, "wanted " .. tostring(want) .. ", got " .. tostring(got))
end

local function load(rel)
  local chunk, err = loadfile(spoon .. rel)
  if not chunk then error("could not load " .. rel .. ", " .. tostring(err)) end
  return chunk()
end

local captureManifest = load("plugins/capture/manifest.lua")
local windowManifest = load("plugins/windowmanager/manifest.lua")
local settingsManifest = load("plugins/systemsettings/manifest.lua")
local launcherManifest = load("host/launcher/manifest.lua")

-- The three contributors and the one query row source that runs its own row, each a fresh
-- copy given the effective defaults its manifest ships, the same values configure receives
-- from the wiring. Capture and the window manager are given only the two fields their rows
-- read, since their own configure validates a provider chain or sets the global window
-- animation duration, and neither is any of this case's business.
local capture = load("plugins/capture/engine.lua")
capture._bindings = captureManifest.defaults.bindings
capture._leader = captureManifest.defaults.leader

local windows = load("plugins/windowmanager/init.lua")
windows._bindings = windowManifest.defaults.bindings
windows._leader = windowManifest.defaults.leader

local settings = load("plugins/systemsettings/init.lua")
settings:init()
settings:configure({ panes = settingsManifest.defaults.panes,
  searchRow = settingsManifest.defaults.searchRow })

local windowSize = load("plugins/windowsize/init.lua")

-- What the composition root does with a contributor's rows, stamp its identity as the owner of
-- the item and of the icon key, by a copy. Restated rather than reached, since the root is one
-- long function and not a module a case can load.
local function own(rows, identity)
  local out = {}
  for i, row in ipairs(rows or {}) do
    local copy, item = {}, {}
    for k, v in pairs(row) do copy[k] = v end
    for k, v in pairs(row.item) do item[k] = v end
    item.owner = identity
    copy.item = item
    if copy.icon ~= nil and copy.image == nil and copy.iconOwner == nil then copy.iconOwner = identity end
    out[i] = copy
  end
  return out
end

local modules = { capture = capture, systemsettings = settings, windowmanager = windows,
  windowsize = windowSize }
local suppliers, runners = {}, {}
for _, identity in ipairs({ "capture", "systemsettings", "windowmanager" }) do
  suppliers[#suppliers + 1] = function() return own(modules[identity]:launcherRows(), identity) end
end
for identity, mod in pairs(modules) do
  runners[identity] = function(item) return mod:launcherRun(item) end
end

-- A chord speller that keeps every part visible, so a subtitle that names the wrong leader,
-- key or modifier reads differently here.
local function chordLabel(leader, key, mods)
  return leader .. " " .. tostring(key) .. (mods and ("+" .. table.concat(mods, "+")) or "")
end

local leafCalls = {}
local launcher = load("host/launcher/init.lua")
launcher:init()
launcher:configure({
  leaderNames = { app = "Hyper", window = "Meta" },
  chordLabel = chordLabel,
  rowSuppliers = suppliers,
  runners = runners,
  specialRows = launcherManifest.defaults.specialRows,
  iconOwner = "launcher",
  predicates = { multipleDisplays = function() return true end },
  actions = {
    app = function(bundleID, url) leafCalls[#leafCalls + 1] = "app " .. bundleID .. " " .. tostring(url) end,
    copy = function(value) leafCalls[#leafCalls + 1] = "copy " .. tostring(value) end,
    special = { lock = function() leafCalls[#leafCalls + 1] = "lock" end },
  },
})
-- No app scan, the catalog rows are the subject here.
launcher._appRows = function() return {} end
launcher:_ensureStaticRows()

--------------------------------------------------------------------------------
-- The rows, as they read.
--------------------------------------------------------------------------------

local actionRows, directoryRows = launcher._actionRows, launcher._directoryRows
local nWindows = #windowManifest.defaults.bindings
local nCapture = #captureManifest.defaults.bindings
eq("every command row is listed", #actionRows, nCapture + 1 + 3 + nWindows)
eq("every pane is listed after the commands", #directoryRows, #settingsManifest.defaults.panes)

-- The untouched order, which is the order the list has always had.
local wantOrder = { "OCR", "Screenshot (copy)", "Screenshot", "Record screen", "Search Settings",
  "Aliases", "Lock Screen", "Sleep", "Previous Display", "Next Display", "Left Half" }
for i, title in ipairs(wantOrder) do
  eq("row " .. i .. " is " .. title, (actionRows[i] or {}).title, title)
end
eq("the last command row is the last window action", actionRows[#actionRows].title,
  "Hide All Except Focused")
eq("the first directory row is the first pane", directoryRows[1].title, "Wi-Fi")

local function expectRow(label, row, want)
  row = row or {}
  local item = row.item or {}
  eq(label .. " title", row.title, want.title)
  eq(label .. " subtitle", row.subTitle, want.subTitle)
  eq(label .. " icon key", row.icon, want.icon)
  eq(label .. " icon owner", row.iconOwner, want.iconOwner)
  eq(label .. " kind", item.kind, want.kind)
  eq(label .. " identifying field", item.name or item.url, want.id)
  eq(label .. " owner", item.owner, want.owner)
  eq(label .. " gate", row.when, want.when)
  eq(label .. " carries no image", row.image, nil)
end

expectRow("capture row", actionRows[3], {
  title = "Screenshot", subTitle = "Capture · Hyper 4+shift", icon = "screenshot",
  iconOwner = "capture", kind = "capture", id = "captureArea", owner = "capture" })
expectRow("search settings row", actionRows[5], {
  title = "Search Settings", subTitle = "System · opens the System Settings search field",
  icon = "search", iconOwner = "systemsettings", kind = "special", id = "searchSettings",
  owner = "systemsettings" })
expectRow("own special row", actionRows[7], {
  title = "Lock Screen", subTitle = "System · Hyper §", icon = "lock", iconOwner = "launcher",
  kind = "special", id = "lock" })
expectRow("gated window row", actionRows[9], {
  title = "Previous Display", subTitle = "Window · Meta ,", icon = "windows",
  iconOwner = "windowmanager", kind = "window", id = "previousDisplay", owner = "windowmanager",
  when = "multipleDisplays" })
expectRow("window row", actionRows[#actionRows], {
  title = "Hide All Except Focused", subTitle = "Window · Meta H", icon = "windows",
  iconOwner = "windowmanager", kind = "window", id = "hideAllExceptFocused",
  owner = "windowmanager" })
expectRow("pane row", directoryRows[1], {
  title = "Wi-Fi", subTitle = "System Settings", icon = "wifi", iconOwner = "systemsettings",
  kind = "settingsPane", id = "x-apple.systempreferences:com.apple.wifi-settings-extension",
  owner = "systemsettings" })
eq("pane row keywords", directoryRows[1].keywords, "wifi wireless internet network")

-- The icon each contributed row names is one its owner declares, drawn the same as the
-- launcher's own copy was, so the picture did not change when the owner did.
local launcherIcons = launcherManifest.icons
eq("the window icon is the one the launcher drew", windowManifest.icons.windows.sf,
  launcherIcons.windows.sf)
eq("the window icon emoji is the one the launcher drew", windowManifest.icons.windows.emoji,
  launcherIcons.windows.emoji)
eq("the search icon is the one the launcher drew", settingsManifest.icons.search.sf, "magnifyingglass")
eq("the search icon emoji is the one the launcher drew", settingsManifest.icons.search.emoji, "🔍")

--------------------------------------------------------------------------------
-- The catalog scopes and the recency keys.
--------------------------------------------------------------------------------

eq("the window scope lists every window action", #launcher:rowsOfKind("window"), nWindows)
eq("the settings scope lists every pane", #launcher:rowsOfKind("settingsPane"),
  #settingsManifest.defaults.panes)
eq("the capture rows keep their kind", #launcher:rowsOfKind("capture"), nCapture)

-- Recency keyed by kind and name, or by url for a pane, exactly the keys persisted before, so a
-- pick remembered under the old build still floats its row to the top.
launcher._mru = { "settingsPane:x-apple.systempreferences:com.apple.wifi-settings-extension",
  "special:searchSettings", "capture:ocrArea", "window:center" }
launcher._orderedRowsCache = nil
local ordered = launcher:_orderedRows()
eq("a remembered pane leads", (ordered[1] or {}).title, "Wi-Fi")
eq("then the remembered search row", (ordered[2] or {}).title, "Search Settings")
eq("then the remembered capture", (ordered[3] or {}).title, "OCR")
eq("then the remembered window action", (ordered[4] or {}).title, "Center")
eq("then the untouched order resumes", (ordered[5] or {}).title, "Screenshot (copy)")
launcher._mru = {}
launcher._orderedRowsCache = nil

--------------------------------------------------------------------------------
-- Dispatch, one row per kind, each reaching its own runner with its own argument.
--------------------------------------------------------------------------------

local calls = {}
capture.capture = function(_, name) calls[#calls + 1] = "capture " .. tostring(name) end
windows.actions = function()
  return setmetatable({}, { __index = function(_, name)
    return function(arg)
      calls[#calls + 1] = "window " .. name .. (type(arg) == "table" and (" " .. arg.width .. "x" .. arg.height) or "")
    end
  end })
end
settings.open = function(_, url) calls[#calls + 1] = "open " .. tostring(url) end
settings.focusSearch = function() calls[#calls + 1] = "focusSearch" end
windowSize._windowActions = function()
  return { exactSize = function(size) calls[#calls + 1] = "exactSize " .. size.width .. "x" .. size.height end }
end

local function run(item)
  calls, leafCalls = {}, {}
  launcher:runItem(item)
  local timer = launcher._runTimer
  if timer then
    timer:fire()
    timer:stop()
  end
  return calls[1] or leafCalls[1]
end

local function itemOf(rows, value)
  for _, row in ipairs(rows) do
    if row.item and (row.item.name == value or row.item.url == value) then return row.item end
  end
end

eq("a capture row reaches capture", run(itemOf(actionRows, "ocrArea")), "capture ocrArea")
eq("a window row reaches the window manager", run(itemOf(actionRows, "maximize")),
  "window maximize")
eq("the search row reaches System Settings", run(itemOf(actionRows, "searchSettings")),
  "focusSearch")
eq("a pane row opens its pane", run(directoryRows[2].item),
  "open x-apple.systempreferences:com.apple.BluetoothSettings")
eq("a typed size reaches the window size plugin",
  run({ kind = "window", name = "exactSize", size = { width = 1920, height = 1080 }, owner = "windowsize" }),
  "exactSize 1920x1080")
eq("an own special row stays the launcher's", run(itemOf(actionRows, "lock")), "lock")
eq("an app row reaches the app action", run({ kind = "app", bundleID = "com.apple.finder" }),
  "app com.apple.finder nil")
eq("a computed row whose owner runs nothing falls through to its kind",
  run({ kind = "calc", value = "42", owner = "arithmetic" }), "copy 42")
