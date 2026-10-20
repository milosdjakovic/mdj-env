-- System Settings' pane actions, in plain Lua.
--
-- A pane action decides by itself whether a press hides System Settings or goes to its pane, in
-- one place, paneToggle. This pins that rule. Hyper and comma, systemsettings.General, opens General
-- and hides System Settings when pressed again while it shows General, as the app toggle it
-- replaced did. A pane key pressed while System Settings shows another pane goes to its own pane
-- rather than hiding the app, and a pane picked from a launcher row counts as the pane shown.
--
-- It needs no Hammerspoon. A small stub answers the one app and records what was hidden, and a
-- fake appfocus records what was opened.
--
-- Run it.
--   lua test/systemsettings.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

local settingsApp = { front = false, windows = 1, hidden = 0 }
function settingsApp:isFrontmost() return self.front end
function settingsApp:allWindows() local w = {} for i = 1, self.windows do w[i] = true end return w end
function settingsApp:hide() self.hidden = self.hidden + 1 self.front = false end
local running = false
local tasks = {}

hs = {
  logger = { new = function() return setmetatable({}, { __index = function() return function() end end }) end },
  application = { get = function() return running and settingsApp or nil end },
  task = { new = function(_, _, args) return { start = function() tasks[#tasks + 1] = args[1] end } end },
}

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %s, wanted %s, got %s", what, tostring(want), tostring(got)))
  end
end

local opened = {}
local appFocus = { openURL = function(bundleID, url)
  opened[#opened + 1] = url
  running, settingsApp.front = true, true
  return "focused"
end }

local manifest = assert(loadfile(here .. "../plugins/systemsettings/manifest.lua"))()
local settings = assert(loadfile(here .. "../plugins/systemsettings/init.lua"))()
settings:init()
settings:configure({ panes = manifest.defaults.panes, appFocus = appFocus,
  deps = { path = function() return "/usr/bin/open" end } })

local byName = {}
for _, a in ipairs(settings:actions()) do byName[a.name] = a end
local GENERAL = "x-apple.systempreferences:com.apple.systempreferences.GeneralSettings"
local WIFI = "x-apple.systempreferences:com.apple.wifi-settings-extension"

eq(byName.General ~= nil and byName.WiFi ~= nil, true, "names: every pane is an action named by its letters and digits")
eq(byName.General.app, "com.apple.systempreferences", "names: each names System Settings as its app")
eq(byName.General.icon, nil, "names: a pane action carries no icon, since nothing reads one")

-- Hyper and comma as it has always behaved.
byName.General.run()
eq(opened[#opened], GENERAL, "general: the first press opens General")
byName.General.run()
eq(settingsApp.hidden, 1, "general: pressed again while it shows General, System Settings hides")
eq(#opened, 1, "general: and nothing is opened")
byName.General.run()
eq(opened[#opened], GENERAL, "general: pressed again while hidden, General opens again")

-- Another pane's key while System Settings shows General goes to that pane.
byName.WiFi.run()
eq(opened[#opened], WIFI, "other pane: a pane key while another pane shows goes to its own pane")
eq(settingsApp.hidden, 1, "other pane: and does not hide the app")
byName.WiFi.run()
eq(settingsApp.hidden, 2, "other pane: pressed again on its own pane, it hides")

-- A pane picked from the launcher counts as the pane shown.
settings:open(GENERAL)
running, settingsApp.front = true, true
byName.WiFi.run()
eq(opened[#opened], WIFI, "row: after a row opened General, the Wi-Fi key goes to Wi-Fi")
eq(settingsApp.hidden, 2, "row: rather than hiding")
settings:open(GENERAL)
byName.General.run()
eq(settingsApp.hidden, 3, "row: after a row opened General, the General key hides it")

-- In front with no window, a press opens rather than hides.
settingsApp.front, settingsApp.windows = true, 0
local before = #opened
byName.General.run()
eq(#opened, before + 1, "no window: a press opens the pane")

print(string.format("systemsettings: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
