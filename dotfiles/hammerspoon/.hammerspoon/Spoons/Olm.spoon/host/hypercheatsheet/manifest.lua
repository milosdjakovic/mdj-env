-- HyperCheatSheet, what it declares about itself.
--
-- A content builder only, triggered by holding the Hyper key, so it has no chooser, no key,
-- and no alias of its own. The one real capability is the shared overlay renderer both cheat
-- sheets draw through, which is why this plugin is nearly, but not entirely, empty.
return {
  needs = {
    -- Drawing is delegated entirely to the shared grid renderer, this spoon only builds the
    -- row model. Required, matching WindowCheatSheet, since this spoon is also only a front
    -- end onto the renderer and has nothing to draw without it.
    lib = {
      cheatSheet = { from = "cheatsheet", policy = "required" },
    },

    data = {
      -- config/apps.lua, the person's own bundle id registry. This plugin resolves a
      -- toggle's app name into a name and an icon through it, so it is this person's own
      -- knowledge rather than something Olm could ship, the same reasoning VPN's relay list
      -- already earns. Optional, since a missing registry only drops the app rows rather
      -- than the whole overlay.
      apps = { source = "user", policy = "optional",
        breaks = "the overlay's app section stays empty, since nothing maps a toggle's app name to a bundle id to resolve a name and an icon from" },
      -- config/keys.lua's appToggles list, the person's own choice of which apps get a
      -- Hyper toggle and on which key. Optional for the same reason apps is, a missing
      -- list only drops the app rows.
      toggles = { source = "user", policy = "optional",
        breaks = "the overlay's app section stays empty, since there is no toggle list to resolve against the app registry" },
      -- The static, non app sections appended after the running and dormant split, assembled
      -- by the root out of several plugins' own bindings. Root computed, since building that
      -- list is composition policy this plugin could not know on its own. Optional, since an
      -- absent list only means the overlay stops at the app split.
      --
      -- What this field cannot say is that the list must enumerate every plugin that actually
      -- carries a Hyper chord. The live root's own list is a hand kept copy that has already
      -- gone stale once, and needs.data only proves a list arrived, never that it is
      -- complete against the rest of the set.
      sections = { source = "root", policy = "optional",
        breaks = "the overlay shows the running and dormant app split and nothing else, since no static service sections are appended after it" },
    },
  },
}
