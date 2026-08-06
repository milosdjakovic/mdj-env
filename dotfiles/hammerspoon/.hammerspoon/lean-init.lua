--- lean-init.lua
---
--- The lean test surface. A minimal composition root that loads only the tool under
--- test and its direct needs, so a live test of that one tool sits in isolation and
--- nothing else the full root wires can be the cause of what the test shows.
--- bin/hs-devlock acquire --lean points MJConfigFile at this file instead of
--- init.lua, and every other rule of the test lock, the stale timeout, --manual,
--- --wait, and release, stays exactly what it is for the full root, since only the
--- file config_for answers with changes.
---
--- Two sections below. The permanent scaffold carries the wiring every lean test
--- needs, hs.ipc, settings, Dependencies, Chooser, and Olm's storage, borrowed from
--- the same seams init.lua wires those through rather than inventing new ones. A
--- later phase testing a different tool swaps only the section marked as the tool
--- under test, and the scaffold above it does not change, other than the one word
--- naming the tool in the scaffold's own announcement, called out where it sits.
---
--- This copy carries Vpn, the phase two live test of the olm side copy at
--- Spoons/Olm.spoon/plugins/vpn, converted to the shared recency service, against
--- the original at Spoons/Vpn.spoon. The two line toggle in the tool section below
--- flips between them, the same shape the full root's own toggle carries, so one
--- comment restores the original.

--------------------------------------------------------------------------------
-- Permanent scaffold. Every future lean test keeps this section as it stands, and
-- swaps only the tool section below it.
--------------------------------------------------------------------------------

-- hs.ipc first, before anything else in this file has a chance to fail, so the
-- port answers even if something later here dies. A dead port on the full root
-- means the load died before reaching its own hs.ipc require near the end of
-- init.lua, per the console rule in this package's CLAUDE.md, and requiring it
-- here first keeps that same signal honest on this much shorter file, a console
-- error for whoever is testing rather than a silent dead port with nothing to read.
require("hs.ipc")

-- One line naming this file and the tool it carries today. The word after
-- carrying is the one piece of this announcement that changes when a later phase
-- swaps the tool section below for its own tool, everything else in this file's
-- permanent scaffold does not.
print("lean-init.lua is live, carrying Vpn")

local settings = require("config.settings")

-- Dependencies first, the one door to every external tool, same reasoning as the
-- full root, so the tool section below reaches its own path through depsFor and
-- never probes for a tool itself.
hs.loadSpoon("Dependencies")
spoon.Dependencies:init()
spoon.Dependencies:configure({})
spoon.Dependencies:start()
local function depsFor(name) return spoon.Dependencies:scope(name) end

-- Chooser, the picker facade the tool below is built on.
hs.loadSpoon("Chooser")
spoon.Chooser:init()

-- Olm, the reusable core, wired with the two storage roots from settings so the
-- shared recency service the tool section builds below persists where the full
-- root's own copy already does.
hs.loadSpoon("Olm")
spoon.Olm.lib.storage.configure(settings.paths)

--------------------------------------------------------------------------------
-- Tool under test. A later phase swaps this whole section, the toggle, the
-- configure fields, the hotkey, and the two console lines, for its own tool.
--------------------------------------------------------------------------------

-- The olm side toggle for Vpn, the same two lines and the same reasoning the full
-- root carries beside its own hs.loadSpoon calls. The olm side copy is active,
-- loaded by dofile off hs.configdir since it bypasses hs.loadSpoon and nothing
-- else does that assignment for it. Comment the line below and uncomment the one
-- under it to load the original instead, and both leave spoon.Vpn set to a module
-- carrying that one name.
spoon.Vpn = dofile(hs.configdir .. "/Spoons/Olm.spoon/plugins/vpn/init.lua")
-- hs.loadSpoon("Vpn")

-- Only the fields the copy actually requires. theme, chooser, and deps are read at
-- start, and recency is required by this copy's own configure, the shared lift to
-- front service built against the same settings key the full root uses, so a
-- remembered city order carries across both this toggle and the one in init.lua.
-- onPositioned, onActivity, and onClose dock the full root's shared shortcut
-- panel, and this surface docks no panel, so they are left out entirely.
spoon.Vpn.configure({
  theme = settings.chooserTheme,
  chooser = spoon.Chooser,
  deps = depsFor("Vpn"),
  recency = spoon.Olm.lib.recency.new({ settingsKey = "Vpn.recentLocations" }),
})
spoon.Vpn.start()

-- One plain hotkey, not routed through HyperKey or ChordKey since neither loads
-- on this surface, so the tester has one obvious way in and never has to guess it.
local LEAN_MODS, LEAN_KEY = { "cmd", "alt", "ctrl" }, "V"
hs.hotkey.bind(LEAN_MODS, LEAN_KEY, function()
  spoon.Vpn.show()
end)
print("press " .. table.concat(LEAN_MODS, "+") .. "+" .. LEAN_KEY .. " to open Vpn")
