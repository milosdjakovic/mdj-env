-- WindowLeader, what it declares about itself.
--
-- A domain adapter over the shared hold, tap, chord engine, owning only the per leader
-- binding tables and the sub-modifier resolution policy. It has no chooser, no key of its
-- own beyond whichever physical key config/keys.lua names as the window leader, and no
-- alias, every binding it carries belongs to whichever domain registered it, so this plugin
-- is nearly, but not entirely, empty.
return {
  needs = {
    -- The engine that actually swallows keys while a leader is held and fires onKey.
    -- Without it, start logs a warning and registers nothing, so every window leader key
    -- goes silently dead, no feedback at the moment of the press and nothing in the
    -- console again after that first warning. This spoon is only a front end onto that
    -- engine, so a dead surface here is worse than no surface, which is what required is
    -- for.
    lib = {
      chord = { from = "chordkey", policy = "required" },
    },

    -- WindowCheatSheet is the overlay this plugin reveals on its own hold and hides on its
    -- own release, a fact about what this plugin does while a leader is held rather than
    -- something the composition root could ever derive from anything else, which is why the
    -- coupling belongs here and not in root/compose.lua. The earlier shape had the root
    -- close over spoon.WindowCheatSheet directly inside the two callbacks it built for this
    -- plugin, an undeclared dependency running the opposite direction from the one this
    -- file otherwise states, WindowManager needing WindowLeader rather than the other way
    -- round, and it left the composition root naming a second plugin under plugins as a
    -- literal, the exact leak that file's own header forbids.
    --
    -- Optional, since a portable install with no cheat sheet plugin still gets a working
    -- window leader. Every chord and every bound key still fires, only the reveal on hold
    -- goes missing, which is exactly what a degraded plugin means and nothing a required
    -- policy would be honest about.
    --
    -- Ordering false, because this collaborator is never read at configure time. It is
    -- closed over inside the hold and release closures configure itself builds below, and
    -- neither one runs until a leader is actually held, long after every plugin's own
    -- configure, WindowCheatSheet's included, has already finished in stage two. Wanting the
    -- capability and wanting it configured first are different claims, and this plugin only
    -- ever makes the first one, the same distinction MenuSearch's own Launcher closures
    -- already rest on.
    siblings = {
      windowCheatSheet = { plugin = "windowcheatsheet", policy = "optional", ordering = false },
    },
  },
}
