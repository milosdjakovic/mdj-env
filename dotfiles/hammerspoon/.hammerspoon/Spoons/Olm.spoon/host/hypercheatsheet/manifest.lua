-- HyperCheatSheet, what it declares about itself.
--
-- A content builder only, triggered by holding the Hyper key, so it has no chooser, no key,
-- and no alias of its own. The one real capability is the shared overlay renderer both cheat
-- sheets draw through, which is why this plugin is nearly, but not entirely, empty.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Hyper Cheat Sheet",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },

  needs = {
    -- Drawing is delegated entirely to the shared grid renderer, this spoon only builds the
    -- row model. Required, matching WindowCheatSheet, since this spoon is also only a front
    -- end onto the renderer and has nothing to draw without it.
    lib = {
      cheatSheet = { from = "cheatsheet", policy = "required" },
    },

    -- Every plugin that adds sections to a leader's sheet. A contributor answers them from its
    -- own cheatSheetSections member, built from its own data, and states the leader they belong
    -- to as defaults.leader, so only the ones on the app leader reach this sheet. Asking the set
    -- is what lets the app toggles appear here while this host names no plugin and reads no
    -- plugin's data, which until phase four of the core split it did.
    set = {
      cheatSheetSections = { provides = { "cheatSheetSections" } },
    },

    data = {
      -- The ordered list of sections, the root's assembly of two sources. This sheet's own
      -- block, every chord the root found bound on the app leader, and one supplier per plugin
      -- answering the set above, each placed by its cheatSheetOrder. Root computed, since only
      -- the root may resolve a member on another plugin's module and only the root knows what
      -- it bound. Optional, since an absent list leaves an overlay with nothing to show rather
      -- than a broken one.
      sections = { source = "root", policy = "optional",
        breaks = "holding Hyper shows an empty overlay, since neither the bound chords nor any plugin's sections are handed over" },
    },
  },

  defaults = {
    -- Where this sheet's own block, every chord bound on the app leader, sits among the
    -- sections plugins contribute, a number compared with each contributor's own
    -- cheatSheetOrder. Fifty follows the app toggles at ten, the order the sheet has always had.
    cheatSheetOrder = 50,
  },
}
