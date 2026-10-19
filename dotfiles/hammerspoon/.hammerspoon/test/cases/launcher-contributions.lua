-- Unit case for the rows other plugins contribute to the launcher's own catalog, phase three of
-- the core split, and since phase 2b of the keymap plan the rows Olm builds from action
-- descriptors. Capture's and the window manager's rows are built by lib/contributions.lua from
-- the descriptors each plugin answers in provides.actions, with the chord the keymap binds, and a
-- chosen one runs its descriptor. System Settings still answers its own rows through
-- provides.launcherRows and runs a chosen one through provides.launcherRun, since a pane is not
-- an action until a later phase. The launcher routes a chosen row by the owner
-- lib/contributions.lua stamps on its item. Before the core split the launcher held seven
-- siblings on four plugins and built these rows itself.
--
-- What is asserted is what a person sees and what the launcher remembers. The titles, the
-- subtitles, the icon keys, the order of an untouched list, and the recency key of every row,
-- since the recency memory persisted in hs.settings is keyed by kind and identifying string and
-- a change would make the launcher forget every pick made before it. The expected words were
-- read off the launcher as it built these rows before the change, by a comparison run against
-- the previous commit, which found every field equal except the owner an icon key is read
-- against. The window rows and the settings search row read theirs against the plugin that
-- built them now, which declares the same emoji and the same SF Symbol the launcher did, so the
-- picture is unchanged.
--
-- The suppliers, the runners and the query row wrapper come from lib/contributions.lua itself,
-- the same module the composition root calls, handed a plan shaped like the real one, so the
-- owner stamping, the order stamping and the member resolution here are the code that runs.
--
-- Last, the app rows. A bound app's chord and url reach its row through the app toggler's
-- provides.launcherAppDetails, merged by lib/contributions.lua, and the launcher reads no person
-- data. The expected subtitles are the ones the launcher wrote when it read the toggles itself.
--
-- Then one row per kind is run through the launcher's own dispatcher and must reach the right
-- runner with the right argument. Every plugin method that would act on the world, take a
-- screenshot, move a window, open a pane, is replaced by a recorder on a fresh copy of the
-- module, so nothing here touches the running config. The deferred run is fired by hand
-- rather than waited for, and stopped, so the case stays synchronous.
--
-- Fresh copies throughout, each module loaded with loadfile straight out of this checkout, so
-- the instance the live config holds is never reached. Under a plain lua interpreter with no
-- Hammerspoon at all, a small stub stands in.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local spoon = caseDir .. "/../../Spoons/Olm.spoon/"

-- Warnings the launcher logs, readable only under the stub, since a live logger keeps its
-- lines to itself.
local warnings = nil
if hs == nil then
  warnings = {}
  hs = {
    settings = { get = function() return nil end, set = function() end },
    processInfo = { bundleID = "org.hammerspoon.Hammerspoon" },
    logger = { new = function()
      return setmetatable({ w = function(msg) warnings[#warnings + 1] = msg end },
        { __index = function() return function() end end })
    end },
    timer = { doAfter = function(_, fn) return { fire = function() fn() end, stop = function() end } end },
    image = { imageFromAppBundle = function() return nil end },
    application = {
      runningApplications = function() return {} end,
      pathForBundleID = function() return "" end,
      nameForBundleID = function() return nil end,
    },
    hotkey = { bind = function() end },
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

local contributions = load("lib/contributions.lua")
local registrar = load("lib/registrar.lua")
local keymapLib = load("lib/keymap.lua")

local manifests = {
  capture = load("plugins/capture/manifest.lua"),
  windowmanager = load("plugins/windowmanager/manifest.lua"),
  systemsettings = load("plugins/systemsettings/manifest.lua"),
  windowsize = load("plugins/windowsize/manifest.lua"),
  launcher = load("host/launcher/manifest.lua"),
}
local captureManifest, windowManifest = manifests.capture, manifests.windowmanager
local settingsManifest, launcherManifest = manifests.systemsettings, manifests.launcher

-- The three contributors and the one query row source that runs its own row, each a fresh
-- copy. Capture and the window manager are not configured, since their own configure validates
-- a provider chain or sets the global window animation duration, and their actions need neither.
local capture = load("plugins/capture/engine.lua")
local windows = load("plugins/windowmanager/init.lua")

local settings = load("plugins/systemsettings/init.lua")
settings:init()
settings:configure({ panes = settingsManifest.defaults.panes,
  searchRow = settingsManifest.defaults.searchRow })

local windowSize = load("plugins/windowsize/init.lua")
windowSize:init()
windowSize:configure({ plan = function(w, h) return { width = w, height = h, clamped = false } end })

local modules = { capture = capture, systemsettings = settings, windowmanager = windows,
  windowsize = windowSize }

-- What the icon door does to a row naming an icon, set its owner when it has none. The icon
-- engine itself is not this case's subject.
local function stampIcons(rows, owner)
  local out = {}
  for i, row in ipairs(rows or {}) do
    if row.icon ~= nil and row.image == nil and row.iconOwner == nil then
      local copy = {}
      for k, v in pairs(row) do copy[k] = v end
      copy.iconOwner = owner
      out[i] = copy
    else
      out[i] = row
    end
  end
  return out
end

-- The plan as the resolver shapes it, the set answers sorted by identity and the effective
-- defaults keyed by identity, with an optional person override merged over one plugin's.
local function planWith(overrides)
  local effective = {}
  for identity, m in pairs(manifests) do
    local merged = {}
    for k, v in pairs(m.defaults or {}) do merged[k] = v end
    for k, v in pairs((overrides or {})[identity] or {}) do merged[k] = v end
    effective[identity] = merged
  end
  return {
    sets = { launcher = {
      launcherRows = { "systemsettings" },
      launcherRun = { "systemsettings", "windowsize" },
    } },
    effective = effective,
    order = { "capture", "launcher", "systemsettings", "windowmanager", "windowsize" },
    identity = {}, contexts = {},
  }
end

-- What each plugin can run, through the registrar's own validation, and the keymap over the
-- plan, the two inputs the root hands lib/contributions.lua for the rows it builds from
-- descriptors. The capture leader is told apart from the window leader by the roles.
local function actionsOf(plan)
  local actions, order = {}, {}
  for _, directory in ipairs(plan.order) do
    local manifest, module = manifests[directory], modules[directory]
    if manifest and (manifest.provides or {}).actions ~= nil then
      local answered, _, _, names = registrar.validateActions(directory, manifest, module)
      actions[directory], order[directory] = answered, names
    end
  end
  local keymap = keymapLib.build({ plan = plan, roles = { app = "HYPER", window = "META" },
    actions = actions, hostRun = function() return nil end })
  return actions, order, keymap
end

-- A chord speller that keeps every part visible, so a subtitle that names the wrong leader,
-- key or modifier reads differently here.
local function chordLabel(leader, key, mods)
  return leader .. " " .. tostring(key) .. (mods and ("+" .. table.concat(mods, "+")) or "")
end

local leafCalls = {}
local function buildLauncher(plan, extraSuppliers)
  local actions, actionOrder, keymap = actionsOf(plan)
  local suppliers, runners = contributions.assemble({
    host = "launcher", plan = plan, manifests = manifests, modules = modules,
    registrar = registrar, stampIcons = stampIcons,
    actions = actions, actionOrder = actionOrder, keymap = keymap,
  })
  for _, s in ipairs(extraSuppliers or {}) do suppliers[#suppliers + 1] = s end
  local launcher = load("host/launcher/init.lua")
  launcher:init()
  launcher:configure({
    leaderNames = { app = "Hyper", window = "Meta" },
    chordLabel = chordLabel,
    rowSuppliers = suppliers,
    runners = runners,
    specialRows = launcherManifest.defaults.specialRows,
    launcherOrder = plan.effective.launcher.launcherOrder,
    iconOwner = "launcher",
    predicates = { multipleDisplays = function() return true end },
    -- A scope that would hint every special name, so an owned row asking it shows up.
    aliasHint = function(name) return name == "searchSettings" and " (HINT)" or "" end,
    queryProviders = { contributions.queryProvider(windowSize, "windowsize", stampIcons) },
    actions = {
      app = function(bundleID, url) leafCalls[#leafCalls + 1] = "app " .. bundleID .. " " .. tostring(url) end,
      copy = function(value) leafCalls[#leafCalls + 1] = "copy " .. tostring(value) end,
      special = {
        lock = function() leafCalls[#leafCalls + 1] = "lock" end,
        searchSettings = function() leafCalls[#leafCalls + 1] = "special searchSettings" end,
      },
    },
  })
  -- No app scan, the catalog rows are the subject here.
  launcher._appRows = function() return {} end
  launcher:_ensureStaticRows()
  return launcher
end

local launcher = buildLauncher(planWith())

--------------------------------------------------------------------------------
-- The rows, as they read.
--------------------------------------------------------------------------------

local actionRows = launcher._actionRows
local nWindows = #windowManifest.defaults.bindings
local nCapture = #captureManifest.defaults.bindings
local nPanes = #settingsManifest.defaults.panes
eq("every catalog row is listed", #actionRows, nCapture + 1 + 3 + nWindows + nPanes)

-- The untouched order, which is the order the list has always had, the panes last.
local wantOrder = { "OCR", "Screenshot (copy)", "Screenshot", "Record screen", "Search Settings",
  "Aliases", "Lock Screen", "Sleep", "Previous Display", "Next Display", "Left Half" }
for i, title in ipairs(wantOrder) do
  eq("row " .. i .. " is " .. title, (actionRows[i] or {}).title, title)
end
local lastWindow = nCapture + 1 + 3 + nWindows
eq("the last window action precedes the panes", actionRows[lastWindow].title, "Hide All Except Focused")
eq("the first pane follows every command", actionRows[lastWindow + 1].title, "Wi-Fi")
eq("the last row is the last pane", actionRows[#actionRows].title, "Device Management")

local function expectRow(label, row, want)
  row = row or {}
  local item = row.item or {}
  eq(label .. " title", row.title, want.title)
  eq(label .. " subtitle", row.subTitle, want.subTitle)
  eq(label .. " icon key", row.icon, want.icon)
  eq(label .. " icon owner", row.iconOwner, want.iconOwner)
  eq(label .. " kind", item.kind, want.kind)
  eq(label .. " identifying field", item.key or item.name, want.id)
  eq(label .. " owner", item.owner, want.owner)
  eq(label .. " gate", row.when, want.when)
  eq(label .. " carries no image", row.image, nil)
end

expectRow("capture row", actionRows[3], {
  title = "Screenshot", subTitle = "Capture · Hyper 4+shift", icon = "screenshot",
  iconOwner = "capture", kind = "capture", id = "captureArea", owner = "capture" })
-- The scope above would hint this name, and an owned row is never asked, so the subtitle is
-- exactly what it always was, the real resolver answering nothing for this name either.
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
-- The key arrives in the keymap's one spelling, lowercased, and the real speller's glyph renderer
-- upper cases a letter, so the live subtitle still reads Meta H. This speller keeps the key as
-- given, which is why the letter is lower here.
expectRow("window row", actionRows[lastWindow], {
  title = "Hide All Except Focused", subTitle = "Window · Meta h", icon = "windows",
  iconOwner = "windowmanager", kind = "window", id = "hideAllExceptFocused",
  owner = "windowmanager" })
expectRow("pane row", actionRows[lastWindow + 1], {
  title = "Wi-Fi", subTitle = "System Settings", icon = "wifi", iconOwner = "systemsettings",
  kind = "settingsPane", id = "x-apple.systempreferences:com.apple.wifi-settings-extension",
  owner = "systemsettings" })
eq("pane row keeps its url", actionRows[lastWindow + 1].item.url,
  "x-apple.systempreferences:com.apple.wifi-settings-extension")
-- A row's declared search terms are a list since 2026-10-17, the contributed phrases its first.
eq("pane row keywords", (actionRows[lastWindow + 1].keywords or {})[1], "wifi, wireless, airport")

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
-- Recency keys, byte identical to the keys persisted before the change.
--------------------------------------------------------------------------------

-- The old rule, written out, kind and name, the url for a pane, nothing for a sized window.
local function oldKey(item)
  if item.kind == "calc" or item.kind == "scope" then return nil end
  if item.kind == "window" and item.size then return nil end
  if item.kind == "app" then return "app:" .. tostring(item.bundleID) end
  if item.kind == "settingsPane" then return "settingsPane:" .. tostring(item.url) end
  return item.kind .. ":" .. tostring(item.name)
end

-- The launcher's own key, read through the query memory, which is handed exactly that key.
local noted
launcher._assoc = { note = function(_, key) noted = key end }
launcher.currentQuery = function() return "q" end
local function keyOf(item)
  noted = nil
  launcher:_noteAssociation(item)
  return noted
end

local mismatched = 0
for _, row in ipairs(actionRows) do
  if keyOf(row.item) ~= oldKey(row.item) then
    mismatched = mismatched + 1
    print("FAIL recency key for " .. tostring(row.title) .. ", wanted " .. tostring(oldKey(row.item))
      .. ", got " .. tostring(keyOf(row.item)))
  end
end
eq("every catalog row keeps its persisted recency key", mismatched, 0)
eq("a pane is remembered by its url", keyOf(actionRows[lastWindow + 1].item),
  "settingsPane:x-apple.systempreferences:com.apple.wifi-settings-extension")

local sized = launcher:_queryRows("1920x1080")[1]
eq("a typed size reaches the launcher as a row", (sized or {}).title, "Resize window")
eq("the query row carries its owner", ((sized or {}).item or {}).owner, "windowsize")
eq("the query row's icon is read against its owner", (sized or {}).iconOwner, "windowsize")
eq("a typed size is never remembered", keyOf((sized or {}).item or {}), nil)
eq("an app keeps its own key", keyOf({ kind = "app", bundleID = "com.apple.finder" }),
  "app:com.apple.finder")
launcher._assoc = nil
launcher.currentQuery = nil

--------------------------------------------------------------------------------
-- The catalog scopes, and the recency order.
--------------------------------------------------------------------------------

eq("the window scope lists every window action", #launcher:rowsOfKind("window"), nWindows)
eq("the settings scope lists every pane", #launcher:rowsOfKind("settingsPane"), nPanes)
eq("the capture rows keep their kind", #launcher:rowsOfKind("capture"), nCapture)

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
-- Placement is a declared number, and a person may move it.
--------------------------------------------------------------------------------

local moved = buildLauncher(planWith({ windowmanager = { launcherOrder = 5 } }))
eq("window actions moved to five lead the list", moved._actionRows[1].title, "Previous Display")
eq("and the screenshot actions follow them", moved._actionRows[nWindows + 1].title, "OCR")

--------------------------------------------------------------------------------
-- An owner is stamped, never chosen, and a collision is named.
--------------------------------------------------------------------------------

-- A supplier that claims another plugin's identity on its row, and a second row answering a
-- kind and name capture already answers. The stamp overwrites the claim.
local forged = contributions.ownRows({
  { title = "Forged", item = { kind = "capture", name = "ocrArea", owner = "capture" } },
}, "windowmanager")
eq("ownRows overwrites a claimed owner", forged[1].item.owner, "windowmanager")
local clashing = buildLauncher(planWith(), { function() return forged end })
local forgedRow
for _, row in ipairs(clashing._actionRows) do if row.title == "Forged" then forgedRow = row end end
eq("the forged row keeps the stamped owner", forgedRow and forgedRow.item.owner, "windowmanager")
if warnings then
  local named = false
  for _, w in ipairs(warnings) do
    if w:find("capture:ocrArea", 1, true) and w:find("'capture'", 1, true)
      and w:find("'windowmanager'", 1, true) then named = true end
  end
  check("two rows answering one kind and name are named with both owners", named)
end

--------------------------------------------------------------------------------
-- Dispatch, one row per kind, each reaching its own runner with its own argument.
--------------------------------------------------------------------------------

-- A descriptor's run calls its plugin's own method when it fires, so replacing the method on the
-- module is enough to record what a chosen row reached.
local calls = {}
capture.capture = function(_, name) calls[#calls + 1] = "capture " .. tostring(name) end
windows.maximize = function() calls[#calls + 1] = "window maximize" end
settings.open = function(_, url) calls[#calls + 1] = "open " .. tostring(url) end
settings.focusSearch = function() calls[#calls + 1] = "focusSearch" end
windowSize._windowActions = function()
  return { { name = "exactSize", run = function(size) calls[#calls + 1] = "exactSize " .. size.width .. "x" .. size.height end } }
end

local function run(item)
  calls, leafCalls = {}, {}
  launcher._runTimer = nil
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
eq("a pane row opens its pane", run(actionRows[lastWindow + 2].item),
  "open x-apple.systempreferences:com.apple.BluetoothSettings")
eq("a typed size reaches the window size plugin through its query row", run(sized.item),
  "exactSize 1920x1080")
eq("an own special row stays the launcher's", run(itemOf(actionRows, "lock")), "lock")
eq("an app row reaches the app action", run({ kind = "app", bundleID = "com.apple.finder" }),
  "app com.apple.finder nil")
eq("a computed row whose owner runs nothing falls through to its kind",
  run({ kind = "calc", value = "42", owner = "arithmetic" }), "copy 42")
eq("an owned special row whose owner runs nothing reaches no tool",
  run({ kind = "special", name = "searchSettings", owner = "arithmetic" }), nil)

--------------------------------------------------------------------------------
-- The app rows. The app toggler builds its rows from a toggle list and supplies what each app
-- with a row shows, and the launcher shows it. The subtitles are the ones the launcher wrote when it read
-- the person's toggles and app registry itself, a modal key spelled with the app leader's name,
-- a literal combo spelled by the glyph function with its description, and a second toggle on
-- one app winning the chord only when it states modifiers while a url from either stays.
--------------------------------------------------------------------------------

local toggler = load("plugins/apptoggler/init.lua")
toggler:init()
-- The toggler binds nothing, it builds a row per toggle in configure and Olm binds them, so no
-- hotkey reaches the live config here.
local bindOk, bindErr = pcall(toggler.configure, toggler, {
  apps = { Alpha = "olm.test.alpha", Beta = "olm.test.beta", Gamma = "olm.test.gamma" },
  appFocus = {},
  toggles = {
    { app = "Alpha", key = "A" },
    { app = "Beta", key = "B", url = "x-test:beta-first" },
    { app = "Beta", key = "8", modifiers = { "ctrl", "alt" }, description = "Placed", url = "x-test:beta" },
    { app = "Gamma", key = "G", modifiers = { "cmd" }, description = "First" },
    { app = "Gamma", key = "H", url = "x-test:gamma" },
  },
})
check("the app toggler builds the probe toggles", bindOk, tostring(bindErr))
check("the app toggler answers one binding row per toggle", bindOk and #toggler:bindings() == 5)

local function appLauncher(details)
  local l = load("host/launcher/init.lua")
  l:init()
  l:configure({
    leaderNames = { app = "Hyper", window = "Meta" },
    glyphFor = function(key, mods) return table.concat(mods or {}, "+") .. " " .. tostring(key) end,
    appDetails = details,
  })
  l._installedApps = {
    ["olm.test.alpha"] = { name = "Alpha", bundleID = "olm.test.alpha" },
    ["olm.test.beta"] = { name = "Beta", bundleID = "olm.test.beta" },
    ["olm.test.gamma"] = { name = "Gamma", bundleID = "olm.test.gamma" },
    ["olm.test.delta"] = { name = "Delta", bundleID = "olm.test.delta" },
  }
  local byId = {}
  for _, row in ipairs(l:_appRows()) do byId[row.item.bundleID] = row end
  return byId
end

local appDetails = contributions.appDetails({
  host = "launcher",
  plan = { sets = { launcher = { launcherAppDetails = { "apptoggler" } } } },
  manifests = { apptoggler = load("plugins/apptoggler/manifest.lua") },
  modules = { apptoggler = toggler },
  registrar = registrar,
})
local apps = appLauncher(appDetails)
eq("a modal toggle's row names the app leader and the key", (apps["olm.test.alpha"] or {}).subTitle,
  "Not running · Hyper A")
eq("a literal combo wins the chord and shows its description", (apps["olm.test.beta"] or {}).subTitle,
  "Not running · ctrl+alt 8 Placed")
eq("the first toggle's url stays when the combo wins the chord", (apps["olm.test.beta"] or {}).item.url,
  "x-test:beta-first")
eq("a later modal toggle does not take the chord from a combo", (apps["olm.test.gamma"] or {}).subTitle,
  "Not running · cmd G First")
eq("a later toggle's url fills an entry that had none", (apps["olm.test.gamma"] or {}).item.url,
  "x-test:gamma")
eq("an app no toggle names carries no chord", (apps["olm.test.delta"] or {}).subTitle, "Not running")

local bare = appLauncher(nil)
eq("with no supplier an app row carries no chord", (bare["olm.test.alpha"] or {}).subTitle, "Not running")
eq("with no supplier an app row opens no url", (bare["olm.test.beta"] or {}).item.url, nil)

local broken = contributions.appDetails({
  host = "launcher",
  plan = { sets = { launcher = { launcherAppDetails = { "broken", "apptoggler" } } } },
  manifests = { apptoggler = load("plugins/apptoggler/manifest.lua"),
    broken = { provides = { launcherAppDetails = "launcherAppDetails" } } },
  modules = { apptoggler = toggler, broken = { launcherAppDetails = function() error("probe") end } },
  registrar = registrar,
})
eq("a supplier that raises costs only its own details", (appLauncher(broken)["olm.test.alpha"] or {}).subTitle,
  "Not running · Hyper A")
