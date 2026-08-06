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
--- This copy carries Clipboard, the phase three live test of the olm side copy at
--- Spoons/Olm.spoon/plugins/clipboard, whose insertion half now lives in the shared
--- engine at Spoons/Olm.spoon/lib/paste.lua, against the original at
--- Spoons/ClipboardHistory.spoon. The boolean in the tool section below flips
--- between them, the same shape the full root's own toggle carries, so one edit
--- restores the original.

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
print("lean-init.lua is live, carrying Clipboard")

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

-- The olm side toggle for Clipboard, one boolean read by the load below, the same
-- shape and the same reasoning the full root carries beside its own. True loads the
-- olm side copy by an absolute path built from hs.configdir, since it bypasses
-- hs.loadSpoon and nothing else does that assignment for it, and false loads the
-- original spoon instead. Both leave spoon.ClipboardHistory set to a module carrying
-- that one name, so everything below reads the same either way.
local CLIPBOARD_ON_OLM = true
if CLIPBOARD_ON_OLM then
  spoon.ClipboardHistory = dofile(hs.configdir .. "/Spoons/Olm.spoon/plugins/clipboard/init.lua")
else
  hs.loadSpoon("ClipboardHistory")
end

-- The message surface. Both keys below change something the tester cannot otherwise
-- see, a position in a list and an entry growing offscreen, so every signal they
-- produce goes through onMessage, a step that pasted and what it was, a file that has
-- gone, the end of history, an empty history, an append that found nothing selected.
-- Without this the walk and the append are silent and there is nothing to judge by eye,
-- which is the whole of the live tier for this phase. The full root draws these on the
-- shared CanvasPanel, which this surface does not load, so hs.alert is enough here, the
-- smallest thing that is visible. Each message closes the one before it rather than
-- stacking, since a burst of walk steps fires one per press and a pile of overlapping
-- alerts hides exactly the behaviour a burst is being watched for.
local leanMessage = nil
local function showLeanMessage(text)
  if leanMessage then
    hs.alert.closeSpecific(leanMessage)
  end
  leanMessage = hs.alert.show(text, 1.2)
end

-- Only the fields this surface actually requires. The chooser factory and the theme
-- because the picker is built from them, the matcher because the list owns its own
-- filtering and calls it directly, the insertion engine because every paste and every
-- selection read the copy makes goes through it, and the message surface above.
-- Everything else the full root passes is presentation or a video preview tool, and
-- none of it is what a paste test looks at. The engine is injected only on the olm
-- side, since the original spoon carries that half inside its own monitor.
spoon.ClipboardHistory.manager.configure({
  chooser = spoon.Chooser,
  theme = settings.chooserTheme,
  matcher = spoon.Chooser.matchers.words,
  paste = CLIPBOARD_ON_OLM and spoon.Olm.lib.paste or nil,
  onMessage = showLeanMessage,
})
spoon.ClipboardHistory.manager.start()

-- Three plain hotkeys, not routed through HyperKey or ChordKey since neither loads on
-- this surface, so the tester has three obvious ways in and never has to guess one.
-- The list, and then the two keys the measurement trail is about, append copy gathering
-- a selection onto the newest entry and paste next walking the history one entry per
-- press, which is the sequence this phase most needs exercised end to end. Those two
-- are the real combos from the full config rather than lean substitutes, because both
-- are pressed mid edit against a physically held chord and that hold is itself one of
-- the things being tested.
local LEAN_MODS, LEAN_KEY = { "cmd", "alt", "ctrl" }, "V"
hs.hotkey.bind(LEAN_MODS, LEAN_KEY, function()
  spoon.ClipboardHistory.manager.show()
end)
local WALK_MODS = { "ctrl", "alt" }
hs.hotkey.bind(WALK_MODS, "C", function()
  spoon.ClipboardHistory.manager.appendCopy()
end)
hs.hotkey.bind(WALK_MODS, "V", function()
  spoon.ClipboardHistory.manager.pasteNext()
end)
local leanCombo = table.concat(LEAN_MODS, "+") .. "+" .. LEAN_KEY
local walkCombo = table.concat(WALK_MODS, "+")
print("press " .. leanCombo .. " to open the clipboard history")
print("press " .. walkCombo .. "+C to append the selection onto the newest entry")
print("press " .. walkCombo .. "+V to paste the next entry in a walk")
